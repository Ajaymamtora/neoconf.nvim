local M = {}

---@class Config
M.defaults = {
  -- Use cwd for neoconf root, prevents searching upwards outside the current project
  root_use_cwd = false,
  -- on_write callback
  on_write = function(event) end,
  -- name of the local settings files
  local_settings = ".neoconf.json",
  -- name of the global settings file in your Neovim config directory
  global_settings = "neoconf.json",
  -- import existing settinsg from other plugins
  import = {
    vscode = true, -- local .vscode/settings.json
    coc = true, -- global/local coc-settings.json
    nlsp = true, -- global/local nlsp-settings.nvim json settings
  },
  -- send new configuration to lsp clients when changing json settings
  live_reload = true,
  -- set the filetype to jsonc for settings files, so you can use comments
  -- make sure you have the jsonc treesitter parser installed!
  filetype_jsonc = true,
  -- keymap for saving temporary settings buffer
  save_keymap = "<leader>s",
  -- LSP change detection method: "auto", "jq", "lua_optimized", "lua_deep"
  -- "auto": try jq first, fallback to lua_optimized
  -- "jq": use jq command for fast JSON comparison
  -- "lua_optimized": use JSON string comparison (fast)
  -- "lua_deep": use original deep recursive comparison (slow but thorough)
  diff_method = "auto",
  plugins = {
    -- configures lsp clients with settings in the following order:
    -- - lua settings passed in lspconfig setup
    -- - global json settings
    -- - local json settings
    lspconfig = {
      enabled = true,
    },
    -- configures jsonls to get completion in .neoconf.json files
    jsonls = {
      enabled = true,
      -- only show completion in json settings for configured lsp servers
      configured_servers_only = true,
    },
    -- configures lua_ls to get completion of lspconfig server settings
    lua_ls = {
      -- by default, lua_ls annotations are only enabled in your neovim config directory
      enabled_for_neovim_config = true,
      -- explicitly enable adding annotations. Mostly relevant to put in your local .neoconf.json file
      enabled = false,
    },
  },
}

--- @type Config
M.options = {}

-- Storage for previous file contents to enable change detection
M._previous_content = {}

---@class SettingsPattern
---@field pattern string
---@field key? string|fun(string):string

---@type SettingsPattern[]
M.local_patterns = {}

---@type SettingsPattern[]
M.global_patterns = {}

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, options or {})

  local util = require("neoconf.util")

  M.local_patterns = {}
  M.global_patterns = {}

  require("neoconf.import").setup()

  vim.list_extend(M.local_patterns, util.expand(M.options.local_settings))
  vim.list_extend(M.global_patterns, util.expand(M.options.global_settings))
  
  -- Initialize previous content for existing config files
  M._previous_content = {}
  util.for_each_global(function(file)
    M.init_previous_content(file)
  end)
  local workspace = require("neoconf.workspace")
  local root_dir = workspace.find_root({})
  if root_dir then
    util.for_each_local(function(file)
      M.init_previous_content(file)
    end, root_dir)
  end
end

---@return Config
function M.merge(options)
  return vim.tbl_deep_extend("force", {}, M.options, options or {})
end

function M.get(opts)
  return require("neoconf").get("neoconf", M.options, opts)
end

-- Initialize previous content for a file
function M.init_previous_content(filepath)
  local util = require("neoconf.util")
  if util.exists(filepath) then
    local data = util.read_file(filepath)
    local ok, json = pcall(vim.json.decode, data)
    if ok then
      M._previous_content[filepath] = json
    else
      M._previous_content[filepath] = {}
    end
  else
    M._previous_content[filepath] = {}
  end
end

-- Get previous content for a file
function M.get_previous_content(filepath)
  return M._previous_content[filepath] or {}
end

-- Update previous content for a file
function M.update_previous_content(filepath, content)
  M._previous_content[filepath] = vim.deepcopy(content)
end

-- Reload previous content for all config files
function M.reload_previous_content()
  local util = require("neoconf.util")
  
  -- Reload global files
  util.for_each_global(function(file)
    M.init_previous_content(file)
  end)
  
  -- Reload local files
  local workspace = require("neoconf.workspace")
  local root_dir = workspace.find_root({})
  if root_dir then
    util.for_each_local(function(file)
      M.init_previous_content(file)
    end, root_dir)
  end
end

return M
