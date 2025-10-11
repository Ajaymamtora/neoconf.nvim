# 💼 neoconf.nvim

**neoconf.nvim** is a Neovim plugin to manage global and project‑local settings **in JSON/JSONC**, with live LSP reloads, schema‑driven completion, and a small but powerful programmatic API (including a safe `set()` writer).

![image](https://user-images.githubusercontent.com/292349/202160538-3711693c-14fd-4e8b-a9d1-ceda88bae00c.png)

---

## ✨ Features

- Configure Neovim using **JSON** (with comments):  
  - **Global**: `~/.config/nvim/neoconf.json`  
  - **Local**:  `<project>/.neoconf.json`
- **Live reload** of LSP settings (sends `workspace/didChangeConfiguration` when relevant config changes)
- Import and merge settings from:
  - [VS Code](https://github.com/microsoft/vscode) (`.vscode/settings.json`)
  - [coc.nvim](https://github.com/neoclide/coc.nvim) (`coc-settings.json`)
  - [nlsp-settings.nvim](https://github.com/tamago324/nlsp-settings.nvim) (`nlsp-settings/*.json`)
- JSON schema & **completion** inside your config files (via `jsonls`)
- Lua annotations & **completion** for LSP settings in your Neovim config (via `lua_ls`)
- **Write API** for scripts and plugins:
  - `require("neoconf").set(path, value[, { scope = "local"|"global" }])`
  - Toggle helpers (`toggle_inlay_hints`, `toggle_boolean`, …)
- Small **UI** helpers to inspect and edit settings

> Tip: Works great alongside `lazydev.nvim` (recommended) or `neodev.nvim` for better Lua dev UX.

---

## ⚡️ Requirements

- Neovim **≥ 0.7.2**
- Optional but recommended:
  - **`jq`** — used for fast diffing/formatting when available
  - **`jsonc`** treesitter parser (if you enable comment support in JSON)

---

## 📦 Installation

Install with your preferred package manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ "folke/neoconf.nvim" }


⸻

🚀 Setup

Set up before nvim-lspconfig.

require("neoconf").setup({
  -- override any of the default settings here (see "Configuration")
})

-- then configure your LSP servers as usual
require("lspconfig").lua_ls.setup(...)


⸻

🧩 Settings Files & Merge Order

Neoconf reads:
	•	Global: stdpath("config")/neoconf.json
	•	Local:  <project>/.neoconf.json

When building LSP settings for a client, the effective config is merged in this order:
	1.	Settings passed to lspconfig.SERVER.setup({ settings = ... })
	2.	Global neoconf: lspconfig.SERVER (from neoconf.json)
	3.	Global imports: coc, nlsp.SERVER
	4.	Local imports:  vscode, coc, nlsp.SERVER
	5.	Local neoconf:  lspconfig.SERVER (from .neoconf.json)

You can disable a server by setting lspconfig.<server> to false in your neoconf JSON.

⸻

⚙️ Configuration

The setup() defaults:

{
  -- Use cwd for neoconf root (prevents searching outside your project)
  root_use_cwd = false,

  -- Called after *any* neoconf JSON file is written (see "Write Callback")
  on_write = function(event) end,

  -- Filenames for settings
  local_settings  = ".neoconf.json",
  global_settings = "neoconf.json",

  -- Import existing settings (merged into LSP configs, never modified)
  import = {
    vscode = true, -- local .vscode/settings.json
    coc    = true, -- global & local coc-settings.json
    nlsp   = true, -- global & local nlsp-settings/*.json
  },

  -- Push didChangeConfiguration to LSP clients when settings change
  live_reload = true,

  -- Treat neoconf files as jsonc (// comments). Requires treesitter parser.
  filetype_jsonc = true,

  -- Keymap to save the temporary editor buffer (see "Editor UI")
  save_keymap = "<leader>s",

  -- How to detect LSP changes under the "lsp" key (affects event.lsp_settings_changed)
  -- "auto": try jq (fast), then fallback to "lua_optimized"
  -- "jq": use jq CLI for diff
  -- "lua_optimized": compare vim.json.encode() strings
  -- "lua_deep": deep recursive table compare (slow but thorough)
  diff_method = "auto",

  plugins = {
    lspconfig = { enabled = true },  -- merge neoconf into lspconfig servers

    jsonls = {                       -- completion in .neoconf.json
      enabled = true,
      configured_servers_only = true,
    },

    lua_ls = {                       -- annotations/types for Lua (your config)
      enabled_for_neovim_config = true,
      enabled = false,
    },
  },
}


⸻

🔄 Write Callback

Hook into writes of neoconf JSON files.

Event object

{
  file = "/abs/path/.neoconf.json",   -- written file
  is_global = false,                   -- true for global file
  current_content = { ... },           -- JSON after write
  previous_content = { ... },          -- JSON before write
  lsp_settings_changed = true,         -- did "lsp" subtree change? (see diff_method)
  raw_event = { ... },                 -- original BufWritePost data
}

Examples

Intelligent LSP restart

require("neoconf").setup({
  on_write = function(event)
    if event.lsp_settings_changed and not event.is_global then
      vim.cmd("LspRestart")
    end
  end,
})

Validate a path

require("neoconf").setup({
  on_write = function(event)
    local lua_ls = event.current_content.lspconfig
      and event.current_content.lspconfig.lua_ls
    if lua_ls and lua_ls.cmd and vim.fn.executable(lua_ls.cmd) == 0 then
      vim.notify(("lua_ls executable not found: %s"):format(lua_ls.cmd), vim.log.levels.WARN)
    end
  end,
})


⸻

🧪 Programmatic API

All functions live under require("neoconf").

get(key?, defaults?, opts?)

Fetch merged settings.

---@generic T : table
---@param key? string           -- dot path; omit to get everything
---@param defaults? T           -- merged when key is missing/partial
---@param opts? { file?:string, buffer?:integer, lsp?:boolean, local?:boolean, global?:boolean }
---@return T
local cfg = require("neoconf").get("myplugin", {enabled = true})

set(path, value[, opts])  — Create path & write safely

Ensure a JSON path exists and set its value, creating intermediate objects as needed. Triggers the same write flow as editing the file (your on_write callback, live reload, cache refresh).

---@param path string                      -- e.g. "lsp.inlay_hint", "lspconfig.lua_ls.settings.Lua.telemetry.enable"
---@param value any                        -- JSON-encodable (string|number|boolean|table|vim.NIL)
---@param opts? { scope?: "local"|"global" } -- default: "local"
---@return boolean|nil ok, string|nil err

-- Examples:
require("neoconf").set("editor.formatOnSave", true)
require("neoconf").set("lsp.inlay_hint", false)
require("neoconf").set("lspconfig.eslint", false)           -- disable a server
require("neoconf").set("lspconfig.lua_ls.settings.Lua.telemetry.enable", vim.NIL) -- JSON null

Notes
	•	Uses vim.json.encode semantics:
	•	lists → JSON arrays; maps → JSON objects
	•	use vim.NIL to encode JSON null
	•	If an intermediate node exists but is not an object (or is a list), it’s
overwritten with an empty object to create the path.
	•	scope="global" writes stdpath("config")/neoconf.json. Default is local.

Helper utilities

-- Toggle a boolean anywhere (local .neoconf.json)
---@return boolean|nil new_value, string|nil err
require("neoconf").toggle_boolean("autoformat")

-- Toggle a string inside a list at path (add/remove)
---@return boolean|nil ok, string|nil err
require("neoconf").toggle_string_in_table("typescript", "features.languages")

-- Toggle LSP inlay hints (writes lsp.inlay_hint in local settings, tries to apply immediately)
---@return boolean|nil new_state
require("neoconf").toggle_inlay_hints()

-- Toggle a generic top-level "autoformat" flag (convention many setups use)
---@return boolean|nil new_state
require("neoconf").toggle_autoformat()

-- Print the current state of a property
require("neoconf").print_property_state("Inlay hints", "lsp.inlay_hint")


⸻

🧷 JSON examples

Per‑server LSP configuration + disabling a server

{
  "lspconfig": {
    "lua_ls": {
      "settings": {
        "Lua": {
          "workspace": { "checkThirdParty": false },
          "diagnostics": { "globals": ["vim"] }
        }
      }
    },
    "eslint": false // disable this server
  }
}

Keep a convenience toggle for your config

{ "autoformat": true, "lsp": { "inlay_hint": true } }

Configure neoconf itself from JSON (optional)

{
  "neoconf": {
    "live_reload": true,
    "filetype_jsonc": true,
    "plugins": { "lua_ls": { "enabled": true } }
  }
}


⸻

🧭 Commands
	•	:Neoconf               – pick a local/global neoconf file to create/edit
	•	:Neoconf local         – pick a local settings file to edit
	•	:Neoconf global        – pick a global settings file to edit
	•	:Neoconf show          – floating window with the merged settings
	•	:Neoconf lsp           – floating window with merged LSP client settings
	•	:Neoconf choose_client – open a temporary buffer with merged (neoconf + selected client) settings
	•	:Neoconf checkhealth   – run health checks

⸻

📝 Editor UI (temporary buffer)
	•	:Neoconf choose_client opens a buffer with:
	•	your merged neoconf settings plus
	•	the selected LSP client’s current settings
	•	Press <leader>s (configurable via save_keymap) to validate & write
only the local .neoconf.json.
	•	This triggers your on_write callback and live reload just like :write.

⸻

🧠 Completion & Validation
	•	JSON: with plugins.jsonls.enabled = true, .neoconf.json files get schema‑based completion and diagnostics. Files are opened as jsonc if you enable filetype_jsonc (so // comments work).
	•	Lua: with plugins.lua_ls active, you get typed completion for lspconfig.* options directly in your config.

Example (typed table of LSP server options):

---@type lspconfig.options
local servers = {
  lua_ls = {},
  jsonls = {
    settings = {
      json = {
        format = { enable = true },
        validate = { enable = true },
      },
    },
  },
}


⸻

🔌 Plugin Author API

Register to extend the JSON schema so users get completion in .neoconf.json:

---@class SettingsPlugin
---@field name string
---@field setup fun()|nil
---@field on_update fun(event)|nil
---@field on_schema fun(schema: Schema)

require("neoconf.plugins").register({
  name = "myplugin",
  on_schema = function(schema)
    -- Auto-generate a JSON schema based on Lua types of your defaults
    schema:import("myplugin", {
      doit = true,
      count = 1,
      array = {},
    })

    -- Optionally refine parts of the generated schema
    schema:set("myplugin.array", {
      description = "Booleans or integers",
      anyOf = { { type = "boolean" }, { type = "integer" } },
    })
  end,
})

-- Later, fetch settings (merged)
local cfg = require("neoconf").get("myplugin", { doit = false, count = 0 })


⸻

🛠 Troubleshooting & Tips
	•	No JSON completion? Check :Neoconf checkhealth. Ensure jsonls is installed and plugins.jsonls.enabled = true.
	•	Comments in JSON look odd? Install the jsonc treesitter parser or disable filetype_jsonc.
	•	LSP doesn’t refresh after editing JSON? Keep live_reload = true. The plugin sends workspace/didChangeConfiguration only when settings actually changed.
	•	Diff performance: set diff_method = "jq" if you have jq installed for fastest comparisons; otherwise lua_optimized is a solid default.
	•	Writing JSON null: use vim.NIL, not nil, when calling set().

⸻

💻 Supported Language Servers

<!-- GENERATED -->


	•	als
	•	astro
	•	awkls
	•	basedpyright
	•	bashls
	•	clangd
	•	cssls
	•	dartls
	•	denols
	•	elixirls
	•	elmls
	•	eslint
	•	flow
	•	fsautocomplete
	•	grammarly
	•	haxe_language_server
	•	hhvm
	•	hie
	•	html
	•	intelephense
	•	java_language_server
	•	jdtls
	•	jsonls
	•	julials
	•	kotlin_language_server
	•	ltex
	•	lua_ls
	•	luau_lsp
	•	omnisharp
	•	perlls
	•	perlnavigator
	•	perlpls
	•	powershell_es
	•	psalm
	•	puppet
	•	purescriptls
	•	pylsp
	•	pyright
	•	r_language_server
	•	rescriptls
	•	rls
	•	rome
	•	ruff_lsp
	•	rust_analyzer
	•	solargraph
	•	solidity_ls
	•	sonarlint
	•	sorbet
	•	sourcekit
	•	spectral
	•	stylelint_lsp
	•	svelte
	•	svlangserver
	•	tailwindcss
	•	terraformls
	•	tinymist
	•	ts_ls
	•	typst_lsp
	•	volar
	•	vtsls
	•	vuels
	•	wgls_analyzer
	•	yamlls
	•	zeta_note
	•	zls

⸻

⭐ Acknowledgment
	•	json.lua — a pure‑Lua JSON library used to parse jsonc files.

