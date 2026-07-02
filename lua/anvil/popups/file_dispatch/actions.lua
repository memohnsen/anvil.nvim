local M = {}

local Process = require("anvil.process")
local git = require("anvil.lib.git")
local notification = require("anvil.lib.notification")
local config = require("anvil.config")

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

local function file_from_env(popup)
  local file = popup:get_env("file")
  if file and file ~= "" then
    return file
  end

  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    notification.warn("Current buffer is not backed by a file")
    return nil
  end

  local root = git.repo.worktree_root
  local abs = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  local nroot = vim.fs.normalize(root)
  if abs:sub(1, #nroot + 1) == nroot .. "/" then
    return abs:sub(#nroot + 2)
  end

  notification.warn(("File %q is not inside the git worktree"):format(name))
  return nil
end

local function refresh_status(source)
  local status = require("anvil.buffers.status")
  if status.instance() then
    status.instance():dispatch_refresh(nil, source)
  end
end

function M.stage(popup)
  local file = file_from_env(popup)
  if file then
    git.cli.add.files(file).call()
    refresh_status("file_dispatch_stage")
  end
end

function M.unstage(popup)
  local file = file_from_env(popup)
  if file then
    git.index.reset { file }
    refresh_status("file_dispatch_unstage")
  end
end

function M.diff(popup)
  local file = file_from_env(popup)
  if file then
    git_cmd { "diff", "--", file }
  end
end

function M.log(popup)
  local file = file_from_env(popup)
  if file then
    git_cmd { "log", "--oneline", "--", file }
  end
end

function M.blame(popup)
  local file = file_from_env(popup)
  if file then
    require("anvil.buffers.blame_view").new(file):open()
  end
end

return M
