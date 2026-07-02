local M = {}

local a = require("neogit.lib.async")
local git = require("neogit.lib.git")
local input = require("neogit.lib.input")
local notification = require("neogit.lib.notification")
local process = require("neogit.process")
local runner = require("neogit.runner")
local event = require("neogit.lib.event")
local state = require("neogit.lib.state")
local config = require("neogit.config")

local HISTORY_LIMIT = 50

---@param cmdline string
local function remember(cmdline)
  local history = state.get({ "run", "history" }, {})
  history = vim.tbl_filter(function(c)
    return c ~= cmdline
  end, history)

  table.insert(history, 1, cmdline)
  while #history > HISTORY_LIMIT do
    table.remove(history)
  end

  state.set({ "run", "history" }, history)
end

---@return string[]
local function history()
  return state.get({ "run", "history" }, {})
end

---@param prompt string
---@return string|nil
local function read_command(prompt)
  return input.get_user_input(prompt, {
    completion = "customlist,v:lua.require'neogit.popups.run.actions'.complete_history",
    separator = " ",
  })
end

---Completion function for command history, used via input's `completion` option
---@param arg_lead string
---@return string[]
function M.complete_history(arg_lead)
  return vim.tbl_filter(function(c)
    return c:find(arg_lead, 1, true) == 1
  end, history())
end

---Run a shell command line, streaming output to the process console.
---@param cmdline string
---@param cwd string
local function run(cmdline, cwd)
  remember(cmdline)

  local proc = process.new {
    cmd = { vim.o.shell, "-c", cmdline },
    cwd = cwd,
    pty = true,
    git_hook = false,
    suppress_console = false,
    user_command = true,
    on_error = function()
      return true
    end,
  }

  local result = runner.call(proc, { pty = true, await = false })
  a.util.scheduler()

  if result and result:failure() then
    notification.warn(("Command exited with code %d"):format(result.code))
  end

  event.send("UserCommandComplete", { cmd = cmdline, cwd = cwd })

  local status = require("neogit.buffers.status")
  if status.instance() then
    status.instance():dispatch_refresh(nil, "run_command")
  end
end

---@return string
local function git_executable()
  return vim.fn.shellescape(config.values.git_executable or "git")
end

---@return string
local function root()
  return git.repo.worktree_root
end

---@return string
local function cwd()
  return vim.uv.cwd() or root()
end

function M.git_command(_)
  local cmd = read_command("git")
  if cmd then
    run(git_executable() .. " " .. cmd, root())
  end
end

function M.git_command_cwd(_)
  local cmd = read_command("git")
  if cmd then
    run(git_executable() .. " " .. cmd, cwd())
  end
end

function M.shell_command(_)
  local cmd = read_command("shell")
  if cmd then
    run(cmd, root())
  end
end

function M.shell_command_cwd(_)
  local cmd = read_command("shell")
  if cmd then
    run(cmd, cwd())
  end
end

function M.wip_snapshot(_)
  git.wip.snapshot()

  local status = require("neogit.buffers.status")
  if status.instance() then
    status.instance():dispatch_refresh(nil, "wip_snapshot")
  end
end

function M.wip_snapshot_index(_)
  local commit = git.wip.snapshot_index()
  if commit then
    notification.info("Index WIP snapshot saved")
  else
    notification.info("No staged changes to snapshot")
  end

  local status = require("neogit.buffers.status")
  if status.instance() then
    status.instance():dispatch_refresh(nil, "wip_snapshot_index")
  end
end

function M.wip_list(_)
  require("neogit.buffers.wip_view").new():open()
end

return M
