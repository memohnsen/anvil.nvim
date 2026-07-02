local M = {}

local Process = require("anvil.process")
local git = require("anvil.lib.git")
local input = require("anvil.lib.input")
local notification = require("anvil.lib.notification")
local config = require("anvil.config")

local FuzzyFinderBuffer = require("anvil.buffers.fuzzy_finder")

local function refresh_status(source)
  local status = require("anvil.buffers.status")
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

local function submodule_paths()
  local paths = git.submodule.list()
  table.sort(paths)
  return paths
end

local function select_submodule(prompt)
  local paths = submodule_paths()
  if #paths == 0 then
    notification.info("No submodules present")
    return nil
  end

  return FuzzyFinderBuffer.new(paths):open_async { prompt_prefix = prompt }
end

function M.add()
  local url = input.get_user_input("Submodule URL")
  if not url then
    return
  end

  local path = input.get_user_input("Submodule path", { completion = "dir" })
  if not path then
    return
  end

  local result = git_cmd { "submodule", "add", url, path }
  if result and result:success() then
    notification.info(("Added submodule %s"):format(path))
    refresh_status("submodule_add")
  end
end

function M.init()
  local result = git_cmd { "submodule", "init" }
  if result and result:success() then
    notification.info("Initialized submodules")
    refresh_status("submodule_init")
  end
end

function M.update(popup)
  local args = { "submodule", "update" }
  vim.list_extend(args, popup:get_arguments())

  local result = git_cmd(args)
  if result and result:success() then
    notification.info("Updated submodules")
    refresh_status("submodule_update")
  end
end

function M.sync()
  local result = git_cmd { "submodule", "sync", "--recursive" }
  if result and result:success() then
    notification.info("Synced submodules")
  end
end

function M.deinit()
  local path = select_submodule("deinit submodule")
  if not path then
    return
  end

  local result = git_cmd { "submodule", "deinit", path }
  if result and result:success() then
    notification.info(("Deinitialized submodule %s"):format(path))
    refresh_status("submodule_deinit")
  end
end

function M.status()
  git_cmd { "submodule", "status", "--recursive" }
end

function M.list()
  require("anvil.buffers.submodule_view").new():open()
end

function M.foreach()
  local command = input.get_user_input("Submodule foreach")
  if not command then
    return
  end

  git_cmd { "submodule", "foreach", "--recursive", command }
end

return M
