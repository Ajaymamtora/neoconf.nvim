-- neoconf/init.lua
local Settings = require("neoconf.settings")
local Util = require("neoconf.util")

local M = {}

function M.setup(opts)
  if require("neoconf.health").check_setup() then
    require("neoconf.util").try(function()
      require("neoconf.config").setup(opts)
      require("neoconf.commands").setup()
      require("neoconf.plugins").setup()
    end)
  end
end

---@generic T : table
---@param key string|nil
---@param defaults T|nil
---@param opts WorkspaceOptions|nil
---@return T
function M.get(key, defaults, opts)
  return require("neoconf.workspace").get(opts).settings:get(key, { defaults = defaults })
end

--- Set a value at a JSON path in neoconf settings, creating intermediate objects as needed.
---
--- Examples:
---   require("neoconf").set("editor.formatOnSave", true)
---   require("neoconf").set("lsp.inlay_hint", false)
---   require("neoconf").set("lspconfig.lua_ls.settings.telemetry.enable", vim.NIL) -- writes `null`
---   require("neoconf").set("my.list", { "a", "b", "c" })
---
--- Notes:
---   • By default writes to the *local* settings file (e.g. `<root>/.neoconf.json`).
---   • Pass opts.scope = "global" to write to the global file (e.g. `<stdpath('config')>/neoconf.json`).
---   • Value must be JSON-encodable by Neovim (`vim.json.encode`). `vim.NIL` becomes JSON `null`.
---
--- @param path string Dot-separated JSON path (e.g. "a.b.c")
--- @param value any JSON-encodable Lua value (string|number|boolean|table|vim.NIL|nil)
--- @param opts? { scope?: "local"|"global" }
--- @return boolean|nil ok  true on success, nil on failure
--- @return string|nil err  error message when ok == nil
function M.set(path, value, opts)
  opts = opts or {}
  local scope = opts.scope or "local"

  if type(path) ~= "string" or path == "" then
    return nil, "path must be a non-empty string"
  end

  -- Validate that the value is JSON-encodable by Neovim.
  do
    local ok, enc_err = pcall(vim.json.encode, value)
    if not ok then
      return nil, ("value is not JSON-serializable: %s"):format(enc_err)
    end
  end

  local Config = require("neoconf.config")
  local Workspace = require("neoconf.workspace")
  local JsonUtil = require("neoconf.utils.json")
  local Commands = require("neoconf.commands")

  -- Resolve target file and current content
  local target_file, current
  if scope == "global" then
    target_file = Util.config_path() .. "/" .. Config.options.global_settings
    local read_tbl = select(1, JsonUtil.read(target_file))
    current = read_tbl or vim.empty_dict() -- force object for empty
  else
    local root_dir = Workspace.find_root({})
    target_file = root_dir .. "/" .. Config.options.local_settings
    current = Settings.get_local(root_dir):get() or vim.empty_dict()
  end

  if type(current) ~= "table" then
    -- If the existing file content is not an object, replace with an empty object.
    current = vim.empty_dict()
  end

  -- Build/ensure the path
  local parts = Settings.path(path)
  if #parts == 0 then
    return nil, "invalid path"
  end

  local node = current
  for i = 1, #parts - 1 do
    local key = parts[i]
    -- Ensure every intermediate node is an object. Override non-tables/lists.
    if type(node[key]) ~= "table" or Util.islist(node[key]) then
      node[key] = vim.empty_dict() -- use empty_dict to force '{}' in JSON, not '[]'
    end
    node = node[key]
  end

  -- Assign leaf
  node[parts[#parts]] = value

  -- Prepare enhanced on_write event info (mirrors BufWritePost handler)
  local previous_content = Config.get_previous_content(target_file)
  if not Config._previous_content[target_file] then
    Config.init_previous_content(target_file)
    previous_content = Config.get_previous_content(target_file)
  end

  -- Persist changes
  local ok, err
  if scope == "global" then
    ok, err = JsonUtil.write(target_file, current, { sort = true, format = false })
  else
    ok = Settings.write_local(current) -- sorts keys; no pretty format to keep diffs small
    if not ok then
      err = "failed to write local settings"
    end
  end

  if not ok then
    return nil, err or "failed to write settings"
  end

  -- Fire user callback and refresh caches similarly to our autocmd path
  local event = {
    file = target_file,
    is_global = (scope == "global"),
    current_content = current,
    previous_content = previous_content,
    lsp_settings_changed = Commands.detect_lsp_changes(previous_content, current),
    raw_event = { match = target_file, via_set_api = true },
  }
  pcall(Config.options.on_write, event)

  -- Track new previous content for future diffs
  Config.update_previous_content(target_file, current)

  -- Clear settings cache for the changed file and notify plugins
  Settings.clear(target_file)
  require("neoconf.plugins").fire("on_update", target_file)

  return true
end

---Toggle a boolean value at a specific settings path
---@param path string The dot-separated path to the setting
---@return boolean|nil new_value The new value after toggling
---@return string|nil error
function M.toggle_boolean(path)
  -- Get current settings first
  local current_settings = Settings.get_local(vim.uv.cwd()):get() or {}
  local current = Settings.get_local(vim.uv.cwd()):get(path)

  -- If value doesn't exist, start with false
  if type(current) ~= "boolean" then
    current = false
  end

  -- Create path to the setting
  local parts = vim.split(path, ".", { plain = true })
  local node = current_settings
  for i = 1, #parts - 1 do
    node[parts[i]] = node[parts[i]] or {}
    node = node[parts[i]]
  end
  -- Toggle the value
  node[parts[#parts]] = not current

  -- Write updated settings back to file
  local success = Settings.write_local(current_settings)
  if not success then
    return nil, "Failed to write settings"
  end

  Settings.refresh()
  return not current
end

---Toggle a string value in a table at a specific settings path
---@param str string The string to toggle
---@param path string The dot-separated path to the array
---@return boolean|nil success
---@return string|nil error
function M.toggle_string_in_table(str, path)
  -- Get current settings first
  local current_settings = Settings.get_local(vim.uv.cwd()):get() or {}
  local current_array = Settings.get_local(vim.uv.cwd()):get(path)

  -- Ensure we have an array to work with
  if type(current_array) ~= "table" then
    current_array = {}
  end

  -- Toggle string in array
  local found = false
  for i, v in ipairs(current_array) do
    if v == str then
      table.remove(current_array, i)
      found = true
      break
    end
  end

  if not found then
    table.insert(current_array, str)
  end

  -- Update the value at path in existing settings
  local parts = vim.split(path, ".", { plain = true })
  local node = current_settings
  for i = 1, #parts - 1 do
    node[parts[i]] = node[parts[i]] or {}
    node = node[parts[i]]
  end
  node[parts[#parts]] = current_array

  -- Write updated settings back to file
  local success = Settings.write_local(current_settings)
  if not success then
    return nil, "Failed to write settings"
  end

  Settings.refresh()
  return true
end

---Helper function to toggle LSP inlay hints
---@return boolean|nil new_state The new state (true for enabled, false for disabled), or nil on error.
function M.toggle_inlay_hints()
  -- 1. Get the resolved value from neoconf (merges global/local)
  -- This correctly uses the workspace/settings resolution logic.
  local current_setting_value = M.get("lsp.inlay_hint")

  -- 2. Determine the *current effective state*
  local current_effective_state
  -- Check if the setting is explicitly set (true or false) vs unset ({})
  if type(current_setting_value) == "boolean" then
    -- Value is explicitly set in neoconf settings (globally or locally)
    current_effective_state = current_setting_value
  else
    -- Value is unset in neoconf settings (M.get returned {} or nil).
    -- Use the fallback: check the *active* Neovim LSP inlay hint state.
    -- Per the requirement: check if the handler table exists.
    -- A more robust check might be vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
    -- but sticking to the requirement:
    current_effective_state = vim.lsp.inlay_hint ~= nil and vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
    -- Defensive check: if vim.lsp.inlay_hint exists, check is_enabled. Handles cases where inlay_hint might exist but isn't active globally.
  end

  -- 3. Calculate the desired new state (toggle the effective state)
  local new_state = not current_effective_state

  -- 4. Prepare to update the *local* settings file only
  -- Read the raw current local settings (don't use M.get here)
  local local_settings_instance = Settings.get_local(vim.uv.cwd())
  local local_settings_table = local_settings_instance and local_settings_instance:get() or vim.empty_dict() -- Use vim.empty_dict() for empty object {}

  -- Ensure the table structure exists
  if type(local_settings_table.lsp) ~= "table" then
    local_settings_table.lsp = vim.empty_dict()
  end

  -- 5. Set the new value in the local settings table
  local local_ok, local_err = pcall(function()
    local_settings_table.lsp.inlay_hint = new_state
  end)
  if not local_ok then
    Util.error("Failed to update inlay_hint in memory: " .. (local_err or "Unknown error"))
    return nil
  end

  -- 6. Write the updated local settings back to the file
  local success, write_err = pcall(Settings.write_local, local_settings_table)
  if not success then
    Util.error("Failed to write local settings for inlay hints: " .. (write_err or "Unknown error"))
    return nil -- Indicate failure
  end

  -- 7. Apply the change to the current Neovim instance
  -- Use pcall in case the buffer doesn't support inlay hints or API changes
  local apply_ok, apply_err = pcall(vim.lsp.inlay_hint.enable, new_state, { bufnr = 0 })
  if not apply_ok then
    Util.warn("Could not apply inlay hint change to buffer: " .. (apply_err or "Unknown error"))
    -- Continue even if applying fails, the setting is saved.
  end

  -- 8. Notify the user
  Util.info("LSP Inlay hints " .. (new_state and "enabled" or "disabled"))

  -- 9. Refresh neoconf's internal cache/state
  Settings.refresh()

  -- 10. Return the new state
  return new_state
end

---Helper function to toggle autoformatting
---@return boolean|nil new_state
function M.toggle_autoformat()
  local new_state = M.toggle_boolean("autoformat")
  if new_state ~= nil then
    Util.info("Autoformat " .. (new_state and "enabled" or "disabled"))
  end
  return new_state
end

---Print the current state of a property
---@param property_name string The name to display in the message
---@param path string|nil The settings path (defaults to property_name)
function M.print_property_state(property_name, path)
  local settings = Settings.get_local(vim.uv.cwd())
  local value = settings:get(path or property_name)
  if value ~= nil then
    Util.info(string.format("'%s' is currently set to: %s", property_name, tostring(value)))
  else
    Util.warn(string.format("'%s' is not set", property_name))
  end
end

return M
