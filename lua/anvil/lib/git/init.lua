local git = require("anvil.lib.git")
local notification = require("anvil.lib.notification")
local input = require("anvil.lib.input")

---@class AnvilGitInit
local M = {}

M.create = function(directory)
  git.cli.init.args(directory).call()
end

M.init_repo = function()
  local directory = input.get_user_input("Create repository in", { completion = "dir" })
  if not directory then
    return
  end

  -- git init doesn't understand ~
  directory = vim.fn.fnamemodify(directory, ":p")

  if vim.fn.isdirectory(directory) == 0 then
    notification.error("Invalid Directory")
    return
  end
  local status = require("anvil.buffers.status")
  if status.is_open() then
    status.instance():chdir(directory)
  end

  if git.cli.is_inside_worktree(directory) then
    vim.cmd.redraw()
    if not input.get_permission(("Reinitialize existing repository %s?"):format(directory)) then
      return
    end
  end

  M.create(directory)
  if status.is_open() then
    status.instance():dispatch_refresh(nil, "InitRepo")
  end
end

return M
