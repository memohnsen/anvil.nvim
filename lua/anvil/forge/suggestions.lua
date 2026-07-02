local notification = require("anvil.lib.notification")

local M = {}

---@param body string|nil
---@return string[]
function M.parse(body)
  if not body or body == "" then
    return {}
  end

  local result = {}
  for suggestion in body:gmatch("```suggestion[^\n]*\n(.-)\n```") do
    local cleaned = suggestion:gsub("\n$", "")
    table.insert(result, cleaned)
  end

  return result
end

---@param topic table
---@return table[]
function M.collect(topic)
  local result = {}

  for thread_idx, thread in ipairs(topic.review_threads or {}) do
    local path = thread.path
    local start_line = thread.start_line or thread.line
    local end_line = thread.line or thread.start_line

    for comment_idx, comment in ipairs(thread.comments or {}) do
      for suggestion_idx, body in ipairs(M.parse(comment.body)) do
        table.insert(result, {
          thread = thread,
          comment = comment,
          thread_idx = thread_idx,
          comment_idx = comment_idx,
          suggestion_idx = suggestion_idx,
          path = path,
          start_line = start_line,
          end_line = end_line,
          body = body,
        })
      end
    end
  end

  return result
end

---@param suggestion table
---@param root string|nil
---@return boolean, string|nil
function M.apply(suggestion, root)
  if not suggestion or not suggestion.path or not suggestion.start_line or not suggestion.end_line then
    return false, "suggestion is missing file or line information"
  end

  root = root or vim.uv.cwd()
  local path = vim.fs.joinpath(root, suggestion.path)
  local lines = vim.fn.readfile(path)
  if vim.v.shell_error ~= 0 then
    return false, "failed to read " .. suggestion.path
  end

  local start_line = tonumber(suggestion.start_line)
  local end_line = tonumber(suggestion.end_line)
  if not start_line or not end_line or start_line < 1 or end_line < start_line or end_line > #lines then
    return false, "suggestion line range is outside the file"
  end

  local replacement = vim.split(suggestion.body or "", "\n", { plain = true })
  if #replacement == 1 and replacement[1] == "" then
    replacement = {}
  end

  vim.list_extend(replacement, vim.list_slice(lines, end_line + 1))
  for idx = start_line, #lines do
    lines[idx] = nil
  end
  vim.list_extend(lines, replacement)

  vim.fn.writefile(lines, path)
  if vim.v.shell_error ~= 0 then
    return false, "failed to write " .. suggestion.path
  end

  notification.info(("Applied suggested change to %s:%d"):format(suggestion.path, start_line))
  return true, nil
end

return M
