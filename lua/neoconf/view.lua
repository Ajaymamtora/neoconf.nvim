local Editor = require("neoconf.editor")
local Settings = require("neoconf.settings")
local Util = require("neoconf.util")

local M = {}

---@param str string
function M.show(str)
  local buf = vim.api.nvim_create_buf(false, false)
  local vpad = 6
  local hpad = 20

  local lines = {}
  for s in str:gmatch("([^\n]*)\n?") do
    table.insert(lines, s)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)

  local opts = {
    relative = "editor",
    width = math.min(vim.o.columns - hpad * 2, 150),
    height = math.min(vim.o.lines - vpad * 2, 50),
    style = "minimal",
    border = "single",
  }

  opts.row = (vim.o.lines - opts.height) / 2
  opts.col = (vim.o.columns - opts.width) / 2

  local win = vim.api.nvim_open_win(buf, true, opts)

  local buf_scope = { buf = buf }
  vim.api.nvim_set_option_value("filetype", "markdown", buf_scope)
  vim.api.nvim_set_option_value("buftype", "nofile", buf_scope)
  vim.api.nvim_set_option_value("bufhidden", "wipe", buf_scope)
  vim.api.nvim_set_option_value("modifiable", false, buf_scope)

  local win_scope = { win = win }
  vim.api.nvim_set_option_value("conceallevel", 3, win_scope)
  vim.api.nvim_set_option_value("spell", false, win_scope)
  vim.api.nvim_set_option_value("wrap", true, win_scope)

  local function close()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<ESC>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufLeave", "BufHidden" }, {
    once = true,
    buffer = buf,
    callback = close,
  })
end

function M.show_lsp_settings()
  local content = {
    "# Lsp Settings\n",
  }
  local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
  for _, client in ipairs(clients) do
    table.insert(content, "## " .. client.name .. "\n")

    for _, item in ipairs(require("neoconf.commands").get_files({ file = client.config.root_dir })) do
      if Util.exists(item.file) then
        local line = "* " .. vim.fn.fnamemodify(item.file, ":~")
        if item.is_global then
          line = line .. "  "
        end
        table.insert(content, line)
      end
    end
    table.insert(content, "```lua\n" .. vim.inspect(client.config.settings) .. "\n```\n")
  end
  M.show(table.concat(content, "\n"))
end

function M.show_settings()
  local content = {
    "# Settings\n",
  }

  for _, item in ipairs(require("neoconf.commands").get_files()) do
    if Util.exists(item.file) then
      local line = "* " .. vim.fn.fnamemodify(item.file, ":~")
      if item.is_global then
        line = line .. "  "
      end
      table.insert(content, line)
    end
  end

  local settings = require("neoconf").get()

  table.insert(content, "```lua\n" .. vim.inspect(settings) .. "\n```\n")
  M.show(table.concat(content, "\n"))
end

-- Display LSP client settings
function M.show_client_settings(client)
  local client_settings = client.config.settings
  local neoconf_settings = require("neoconf").get()

  if next(client_settings) ~= nil or next(neoconf_settings) ~= nil then
    local merged = vim.tbl_deep_extend("force", {}, neoconf_settings, client_settings)
    Editor.open(merged, {
      on_save = function()
        Settings.refresh()
      end,
    })
  else
    Util.warn("No settings found for " .. client.name .. " or in neoconf")
  end
end

-- Choose and display LSP client settings
function M.choose_client()
  local clients = vim.lsp.get_clients()

  if #clients == 0 then
    M.show_local_settings()
  else
    local choices = {
      { name = "Local Settings (No LSP merge)", action = M.show_local_settings },
    }
    for _, client in ipairs(clients) do
      table.insert(choices, {
        name = client.name,
        action = function()
          M.show_client_settings(client)
        end,
      })
    end

    vim.ui.select(choices, {
      prompt = "Choose settings to modify:",
      format_item = function(choice)
        return choice.name
      end,
    }, function(choice)
      if choice then
        choice.action()
      end
    end)
  end
end

-- Show local settings
function M.show_local_settings()
  local settings = Settings.get_local(vim.uv.cwd()):get()
  Editor.open(settings or {}, {
    on_save = function()
      Settings.refresh()
    end,
  })
end

return M
