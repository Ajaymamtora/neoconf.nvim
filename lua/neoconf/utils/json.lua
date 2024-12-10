local uv = vim.uv or vim.loop

local M = {}

---@class JsonEncodeOptions
---@field sort boolean Sort object keys
---@field format boolean Format JSON output

---Encode a Lua table to JSON
---@param value any The value to encode
---@param opts JsonEncodeOptions|nil
---@return string
function M.encode(value, opts)
  opts = vim.tbl_extend("force", { sort = false, format = true }, opts or {})

  -- Basic JSON encode
  local ok, json = pcall(vim.json.encode, value)
  if not ok then
    error("Failed to encode JSON: " .. json)
  end

  -- Format with jq if requested
  if opts.format or opts.sort then
    local args = { "jq" }
    if opts.sort then
      table.insert(args, "--sort-keys")
    end
    table.insert(args, ".")

    local result = vim.fn.system(args, json)
    if vim.v.shell_error == 0 then
      return result
    end
    -- Fallback to unformatted JSON if jq fails
    return json
  end

  return json
end

---Write JSON to a file
---@param filepath string
---@param content any
---@param opts JsonEncodeOptions|nil
---@return boolean success, string? error
function M.write(filepath, content, opts)
  -- Encode content
  local ok, data = pcall(M.encode, content, opts)
  if not ok then
    return false, "Failed to encode JSON"
  end

  -- Write to file
  local fd = uv.fs_open(filepath, "w", 438) -- 0666 octal
  if not fd then
    return false, "Could not open file for writing"
  end

  local success = pcall(function()
    uv.fs_write(fd, data, 0)
    uv.fs_close(fd)
  end)

  if not success then
    return false, "Failed to write file"
  end

  return true
end

---Read JSON from a file
---@param filepath string
---@return table|nil content
---@return string|nil error
function M.read(filepath)
  local fd = uv.fs_open(filepath, "r", 438)
  if not fd then
    return nil, "Could not open file"
  end

  local stat = uv.fs_fstat(fd)
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if not data then
    return nil, "Could not read file"
  end

  local ok, content = pcall(vim.json.decode, data)
  if not ok then
    return nil, "Failed to decode JSON"
  end

  return content
end

return M
