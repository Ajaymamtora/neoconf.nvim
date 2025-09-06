local Config = require("neoconf.config")
local Json = require("neoconf.utils.json")
local Settings = require("neoconf.settings")
local Util = require("neoconf.util")

local M = {}

-- Cache directory for temporary files
M.TMP_DIR = vim.fn.stdpath("cache") .. "/.neoconf_tmp"

---@class EditorOptions
---@field on_save fun()|nil Called after saving settings
---@field on_close fun()|nil Called when closing the editor

---Create a temporary JSON file
---@return string filepath
function M.create_temp_file()
  vim.fn.mkdir(M.TMP_DIR, "p")
  local random_name = vim.fn.system("openssl rand -hex 8"):gsub("\n", "")
  return M.TMP_DIR .. "/" .. random_name .. ".json"
end

---Open settings in a new buffer
---@param settings table The settings to edit
---@param opts EditorOptions|nil
---@return number bufnr
function M.open(settings, opts)
  opts = vim.tbl_deep_extend("force", {
    on_save = function() end,
    on_close = function() end,
  }, opts or {})

  local temp_file = M.create_temp_file()

  -- Ensure empty settings are handled as an empty object
  if settings == nil or next(settings) == nil then
    settings = vim.empty_dict() -- Use vim.empty_dict() to force object notation
  end

  local formatted = Json.encode(settings, { sort = true })

  -- Write formatted content to temp file
  local lines = vim.split(formatted, "\n")
  local write_result = vim.fn.writefile(lines, temp_file)
  if write_result ~= 0 then
    error("Failed to write temporary file: " .. temp_file)
  end

  -- Open in new tab
  vim.cmd("tabnew " .. temp_file)
  local buf = vim.api.nvim_get_current_buf()

  -- Mark as temporary buffer
  vim.api.nvim_buf_set_var(buf, "is_temp_settings_buffer", true)
  vim.api.nvim_buf_set_var(buf, "temp_file_path", temp_file)

  -- Setup buffer
  vim.api.nvim_buf_set_option(buf, "filetype", "json")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Save keymap
  local save_keymap = Config.get().save_keymap or "<leader>s"
  vim.keymap.set("n", save_keymap, function()
    M.save_current_buffer()
    opts.on_save()
  end, { buffer = buf, noremap = true, silent = true })

  -- Clean up on buffer close
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = buf,
    once = true,
    callback = function()
      os.remove(temp_file)
      opts.on_close()
    end,
  })

  return buf
end

---Save the current buffer settings
function M.save_current_buffer()
  local buf = vim.api.nvim_get_current_buf()

  -- Verify this is a settings buffer
  if not pcall(vim.api.nvim_buf_get_var, buf, "is_temp_settings_buffer") then
    Util.error("This is not a temporary settings buffer")
    return
  end

  -- Get current content
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Validate JSON
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    Util.error("Invalid JSON. Please check your changes")
    return
  end

  -- Write to local config
  local success = Settings.write_local(decoded)
  if success then
    Util.info("Settings saved successfully")
    
    -- Call the on_write callback like BufWritePost would
    local Config = require("neoconf.config")
    if Config.options.on_write then
      local root_dir = require("neoconf.workspace").find_root({})
      local local_file = root_dir .. "/" .. Config.options.local_settings
      
      -- Get previous content from our tracking (initialize if new file)
      local previous_content = Config.get_previous_content(local_file)
      if not Config._previous_content[local_file] then
        Config.init_previous_content(local_file)
        previous_content = Config.get_previous_content(local_file)
      end
      
      -- Create enhanced event info (similar to commands.lua)
      local enhanced_event = {
        file = local_file,
        is_global = false,
        current_content = decoded,
        previous_content = previous_content,
        lsp_settings_changed = require("neoconf.commands").detect_lsp_changes(previous_content, decoded),
        raw_event = { match = local_file, via_editor = true }
      }
      
      pcall(Config.options.on_write, enhanced_event)
      
      -- Update previous content for next time
      Config.update_previous_content(local_file, decoded)
    end
    
    Settings.refresh()
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

---Close all temporary settings buffers
function M.close_all()
  local closed = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local is_temp = pcall(vim.api.nvim_buf_get_var, buf, "is_temp_settings_buffer")
    if is_temp then
      local file = vim.api.nvim_buf_get_name(buf)
      os.remove(file)
      vim.api.nvim_buf_delete(buf, { force = true })
      closed = closed + 1
    end
  end
  if closed > 0 then
    Util.info(string.format("Closed %d temporary settings buffer(s)", closed))
  end
end

return M
