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

---Toggle a boolean value at a specific settings path
---@param path string The dot-separated path to the setting
---@return boolean|nil new_value The new value after toggling
---@return string|nil error
function M.toggle(path)
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
  local settings = Settings.get_local(vim.uv.cwd())
  local current = settings:get(path)

  if type(current) ~= "table" then
    current = {}
  end

  -- Toggle string in array
  local found = false
  for i, v in ipairs(current) do
    if v == str then
      table.remove(current, i)
      found = true
      break
    end
  end

  if not found then
    table.insert(current, str)
  end

  -- Create new settings
  local new_settings = {}
  local parts = vim.split(path, ".", { plain = true })
  local node = new_settings
  for i = 1, #parts - 1 do
    node[parts[i]] = {}
    node = node[parts[i]]
  end
  node[parts[#parts]] = current

  -- Write to local settings
  local success = Settings.write_local(new_settings)
  if not success then
    return nil, "Failed to write settings"
  end

  Settings.refresh()
  return true
end

---Helper function to toggle LSP inlay hints
---@return boolean|nil new_state
function M.toggle_inlay_hints()
  local new_state = M.toggle("lsp.inlay_hint")
  if new_state ~= nil then
    vim.lsp.inlay_hint.enable(0, new_state)
    Util.info("Inlay hints " .. (new_state and "enabled" or "disabled"))
  end
  return new_state
end

---Helper function to toggle autoformatting
---@return boolean|nil new_state
function M.toggle_autoformat()
  local new_state = M.toggle("autoformat")
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
