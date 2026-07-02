local Buffer = require("neogit.lib.buffer")
local Process = require("neogit.process")
local config = require("neogit.config")
local git = require("neogit.lib.git")
local notification = require("neogit.lib.notification")

local M = {}
M.__index = M

local function run(args)
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

function M.new(items)
  local submodules = items or git.submodule.list()
  table.sort(submodules)

  return setmetatable({
    items = submodules,
    buffer = nil,
  }, M)
end

function M:item_at_cursor()
  return self.items[vim.fn.line(".") - 3]
end

function M:refresh()
  self.items = git.submodule.list()
  table.sort(self.items)
  self:render()
end

function M:run_selected(action)
  local path = self:item_at_cursor()
  if not path then
    notification.warn("No submodule selected")
    return
  end

  local args = action == "deinit" and { "submodule", "deinit", path }
    or action == "sync" and { "submodule", "sync", "--", path }
    or { "submodule", "update", "--", path }

  local result = run(args)
  if result and result:success() then
    notification.info(("Submodule %s: %s"):format(action, path))
    self:refresh()
  end
end

function M:render(buffer)
  buffer = buffer or self.buffer
  if not buffer then
    return
  end

  local title = "Neogit Submodules"
  local lines = { title, string.rep("=", #title), "" }
  if #self.items == 0 then
    table.insert(lines, "No submodules")
  else
    for _, path in ipairs(self.items) do
      table.insert(lines, path)
    end
  end

  buffer:set_buffer_option("modifiable", true)
  buffer:set_lines(0, -1, false, lines)
  buffer:set_buffer_option("modifiable", false)
end

function M:open(kind)
  self.buffer = Buffer.create {
    name = "NeogitSubmodules",
    filetype = "NeogitSubmodules",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["u"] = function()
          self:run_selected("update")
        end,
        ["s"] = function()
          self:run_selected("sync")
        end,
        ["d"] = function()
          self:run_selected("deinit")
        end,
        ["g"] = function()
          self:refresh()
        end,
        ["q"] = function(buffer)
          buffer:close()
        end,
        ["<esc>"] = function(buffer)
          buffer:close()
        end,
      },
    },
    initialize = function(buffer)
      self:render(buffer)
    end,
  }

  return self
end

return M
