local Process = require("anvil.process")
local config = require("anvil.config")
local git = require("anvil.lib.git")

local M = {}

---@param args string[]
---@param opts { cwd: string|nil, refresh: string|false|nil }|nil
---@return ProcessResult|nil
function M.run(args, opts)
  opts = opts or {}

  local cmd = { config.values.git_executable or "git" }
  vim.list_extend(cmd, args)

  local proc = Process.new {
    cmd = cmd,
    cwd = opts.cwd or git.repo.worktree_root or vim.uv.cwd(),
    on_error = function()
      return true
    end,
  }

  local result = proc:spawn_async()
  if result and result:success() and opts.refresh ~= false then
    local status = require("anvil.buffers.status")
    if status.instance() then
      status.instance():dispatch_refresh(nil, opts.refresh or "git_command")
    end
  end

  return result
end

return M
