local Config = require("neoconf.config")
local Settings = require("neoconf.settings")
local Util = require("neoconf.util")

local M = {}

-- Original deep recursive comparison method (thorough but slow)
local function lua_compare_lsp_deep(previous, current)
  local MAX_DEPTH = 1000
  local visited = {}

  local function deep_equal(a, b, depth)
    -- Recursion depth failsafe
    if depth > MAX_DEPTH then
      return false -- Assume different if too deep to prevent stack overflow
    end

    -- Fast path: identical references
    if a == b then
      return true
    end

    -- Type check
    if type(a) ~= type(b) then
      return false
    end
    if type(a) ~= "table" then
      return false
    end

    -- Circular reference detection
    local key_a = tostring(a)
    local key_b = tostring(b)
    if visited[key_a] or visited[key_b] then
      return a == b -- Only equal if same reference for circular structures
    end
    visited[key_a] = true
    visited[key_b] = true

    -- Compare table contents
    for k, v in pairs(a) do
      if not deep_equal(v, b[k], depth + 1) then
        return false
      end
    end
    for k, v in pairs(b) do
      if a[k] == nil then
        return false
      end
    end

    -- Clean up visited tracking
    visited[key_a] = nil
    visited[key_b] = nil

    return true
  end

  -- Check if the lsp object has changed
  local prev_lsp = type(previous) == "table" and previous.lsp or nil
  local curr_lsp = type(current) == "table" and current.lsp or nil

  return not deep_equal(prev_lsp, curr_lsp, 0)
end

-- Performance-optimized LSP change detection using jq with Lua fallback
local function jq_compare_lsp(previous, current)
  local tempfile_prev = vim.fn.tempname() .. ".json"
  local tempfile_curr = vim.fn.tempname() .. ".json"
  
  -- Write temporary files for jq processing
  local prev_lsp = type(previous) == "table" and previous.lsp or {}
  local curr_lsp = type(current) == "table" and current.lsp or {}
  
  local prev_file = io.open(tempfile_prev, "w")
  if prev_file then
    prev_file:write(vim.json.encode(prev_lsp))
    prev_file:close()
  else
    return nil -- Fallback to Lua
  end
  
  local curr_file = io.open(tempfile_curr, "w")
  if curr_file then
    curr_file:write(vim.json.encode(curr_lsp))
    curr_file:close()
  else
    os.remove(tempfile_prev)
    return nil -- Fallback to Lua
  end
  
  -- Use jq to compare JSON structures efficiently
  local cmd = string.format(
    'jq -s --exit-status ".[0] == .[1]" "%s" "%s" 2>/dev/null',
    tempfile_prev, tempfile_curr
  )
  
  local exit_code = os.execute(cmd)
  
  -- Clean up temporary files
  os.remove(tempfile_prev)
  os.remove(tempfile_curr)
  
  -- jq exits with 0 if equal, 1 if different, >1 if error
  if exit_code == 0 then
    return false -- No change
  elseif exit_code == 256 then -- exit code 1 in Lua (256 = 1 << 8)
    return true -- Change detected
  else
    return nil -- Error, fallback to Lua
  end
end

-- Optimized Lua fallback for LSP comparison
local function lua_compare_lsp_optimized(previous, current)
  local prev_lsp = type(previous) == "table" and previous.lsp or nil
  local curr_lsp = type(current) == "table" and current.lsp or nil
  
  -- Fast path: identical references or both nil
  if prev_lsp == curr_lsp then
    return false
  end
  
  -- One is nil, other is not
  if (prev_lsp == nil) ~= (curr_lsp == nil) then
    return true
  end
  
  -- Convert to JSON strings and compare (much faster than deep recursion)
  local prev_json = vim.json.encode(prev_lsp)
  local curr_json = vim.json.encode(curr_lsp)
  
  return prev_json ~= curr_json
end

-- Helper function to detect LSP-related changes
function M.detect_lsp_changes(previous, current)
  local Config = require("neoconf.config")
  local diff_method = Config.options.diff_method or "auto"
  
  if diff_method == "jq" then
    local jq_result = jq_compare_lsp(previous, current)
    if jq_result ~= nil then
      return jq_result
    end
    -- Fallback to optimized if jq fails
    return lua_compare_lsp_optimized(previous, current)
  elseif diff_method == "lua_optimized" then
    return lua_compare_lsp_optimized(previous, current)
  elseif diff_method == "lua_deep" then
    return lua_compare_lsp_deep(previous, current)
  else -- "auto" or any other value
    -- Try jq-based comparison first (fastest)
    local jq_result = jq_compare_lsp(previous, current)
    if jq_result ~= nil then
      return jq_result
    end
    
    -- Fallback to optimized Lua comparison
    return lua_compare_lsp_optimized(previous, current)
  end
end

function M.setup()
  local commands = {
    lsp = function()
      require("neoconf.view").show_lsp_settings()
    end,
    show = function()
      require("neoconf.view").show_settings()
    end,
    ["local"] = function()
      M.edit({ ["global"] = false })
    end,
    global = function()
      M.edit({ ["local"] = false })
    end,
    checkhealth = function()
      vim.cmd([[checkhealth neoconf]])
    end,
    choose_client = function()
      require("neoconf.view").choose_client()
    end,
  }

  vim.api.nvim_create_user_command("Neoconf", function(args)
    local cmd = vim.trim(args.args or "")
    if commands[cmd] then
      commands[cmd]()
    else
      M.edit()
    end
  end, {
    nargs = "?",
    desc = "Neovim Settings",
    complete = function(f, line, ...)
      if line:match("^%s*Neoconf %w+ ") then
        return {}
      end
      local prefix = line:match("^%s*Neoconf (%w*)")
      return vim.tbl_filter(function(key)
        return key:find(prefix) == 1
      end, vim.tbl_keys(commands))
    end,
  })

  local group = vim.api.nvim_create_augroup("Neoconf", { clear = true })

  if Config.options.live_reload then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = Util.file_patterns({ autocmd = true }),
      group = group,
      callback = function(event)
        local fname = Util.fqn(event.match)
        local is_global = Util.is_global(fname)

        -- Read the current content to detect changes
        local current_content = {}
        if Util.exists(fname) then
          local data = Util.read_file(fname)
          local ok, json = pcall(vim.json.decode, data)
          if ok then
            current_content = json
          end
        end

        -- Get previous content from our tracking (initialize if new file)
        local previous_content = Config.get_previous_content(fname)
        if not Config._previous_content[fname] then
          Config.init_previous_content(fname)
          previous_content = Config.get_previous_content(fname)
        end
        
        -- Create enhanced event info
        local enhanced_event = {
          file = fname,
          is_global = is_global,
          current_content = current_content,
          previous_content = previous_content,
          raw_event = event,
        }

        -- Detect LSP-related changes
        enhanced_event.lsp_settings_changed = M.detect_lsp_changes(previous_content, current_content)
        
        pcall(Config.options.on_write, enhanced_event)
        
        -- Update previous content for next time
        Config.update_previous_content(fname, current_content)

        -- clear cached settings for this file
        Settings.clear(fname)
        require("neoconf.plugins").fire("on_update", fname)
      end,
    })
  end

  if Config.options.filetype_jsonc then
    if vim.g.do_legacy_filetype then
      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        pattern = Util.file_patterns({ autocmd = true }),
        group = group,
        callback = function(event)
          vim.api.nvim_set_option_value("filetype", "jsonc", {
            buf = event.buf,
            scope = "local",
          })
        end,
      })
    else
      vim.filetype.add(Util.filetype_patterns())
    end
  end
end

function M.get_files(opts)
  opts = opts or {}
  opts["local"] = opts["local"] == nil and true or opts["local"]
  opts["global"] = opts["global"] == nil and true or opts["global"]

  local items = {}

  if opts["global"] then
    Util.for_each_global(function(file)
      table.insert(items, { file = file, is_global = true })
    end)
  end

  if opts["local"] then
    local root_dir = require("neoconf.workspace").find_root({ lsp = true, file = opts.file })
    Util.for_each_local(function(f)
      table.insert(items, { file = f })
    end, root_dir)
  end

  -- return files that exist or the default files.
  -- never return imported file patterms that don't exist
  return vim.tbl_filter(function(item)
    item.file = vim.fs.normalize(item.file)
    if Util.exists(item.file) then
      return true
    end
    if not item.is_global and item.file:find("/" .. Config.options.local_settings) then
      return true
    end
    if item.is_global and item.file:find("/" .. Config.options.global_settings) then
      return true
    end
  end, items)
end

function M.edit(opts)
  opts = opts or {}

  local files = M.get_files(opts)

  if #files == 1 then
    vim.cmd("edit " .. files[1].file)
    return
  end

  local edit = {}
  local create = {}
  for _, item in ipairs(files) do
    local l = Util.exists(item.file) and edit or create
    table.insert(l, 1, item)
  end
  files = vim.list_extend(edit, create)

  vim.ui.select(files, {
    prompt = "Select the settings file to create/edit",
    format_item = function(item)
      local line = Util.exists(item.file) and "  edit " or "  create "
      line = line .. vim.fn.fnamemodify(item.file, ":~")
      if item.is_global then
        line = line .. "  "
      end
      return line
    end,
  }, function(choice)
    if choice then
      vim.cmd("edit " .. choice.file)
    end
  end)
end

return M
