local M = {}

local Process = require("neogit.process")
local git = require("neogit.lib.git")
local input = require("neogit.lib.input")
local notification = require("neogit.lib.notification")
local config = require("neogit.config")

local function refresh_status(source)
  local status = require("neogit.buffers.status")
  if status.instance() then
    status.instance():dispatch_refresh(nil, source)
  end
end

local function git_cmd(args)
  local cmd = { config.values.git_executable or "git" }
  vim.list_extend(cmd, args)

  local proc = Process.new {
    cmd = cmd,
    cwd = git.repo.worktree_root,
    on_error = function()
      return true
    end,
  }

  return proc:spawn_async()
end

local function read_rev(prompt, default)
  return input.get_user_input(prompt, { default = default or "" })
end

function M.format_patch(popup)
  local rev = read_rev("Format patch range", "HEAD")
  if not rev then
    return
  end

  local result = git_cmd(vim.list_extend({ "format-patch" }, vim.list_extend(popup:get_arguments(), { rev })))
  if result and result:success() then
    notification.info("Created patch files")
  end
end

function M.format_patch_to_directory(popup)
  local rev = read_rev("Format patch range", "HEAD")
  if not rev then
    return
  end

  local dir = input.get_user_input("Output directory", { completion = "dir" })
  if not dir then
    return
  end

  local args = { "format-patch", "-o", dir }
  vim.list_extend(args, popup:get_arguments())
  table.insert(args, rev)

  local result = git_cmd(args)
  if result and result:success() then
    notification.info(("Created patch files in %s"):format(dir))
  end
end

function M.am(popup)
  local patch = input.get_user_input("Apply mailbox/patch", { completion = "file" })
  if not patch then
    return
  end

  local args = { "am" }
  vim.list_extend(args, popup:get_arguments())
  table.insert(args, patch)

  local result = git_cmd(args)
  if result and result:success() then
    notification.info("Applied patch mailbox")
    refresh_status("patch_am")
  end
end

function M.am_continue()
  local result = git_cmd { "am", "--continue" }
  if result and result:success() then
    notification.info("Continued patch application")
    refresh_status("patch_am_continue")
  end
end

function M.am_skip()
  local result = git_cmd { "am", "--skip" }
  if result and result:success() then
    notification.info("Skipped patch")
    refresh_status("patch_am_skip")
  end
end

function M.am_abort()
  local result = git_cmd { "am", "--abort" }
  if result and result:success() then
    notification.info("Aborted patch application")
    refresh_status("patch_am_abort")
  end
end

function M.apply(popup)
  local patch = input.get_user_input("Apply patch", { completion = "file" })
  if not patch then
    return
  end

  local args = { "apply" }
  vim.list_extend(args, popup:get_arguments())
  table.insert(args, patch)

  local result = git_cmd(args)
  if result and result:success() then
    notification.info("Applied patch")
    refresh_status("patch_apply")
  end
end

return M
