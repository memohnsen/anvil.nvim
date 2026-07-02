local Buffer = require("neogit.lib.buffer")
local notification = require("neogit.lib.notification")
local git = require("neogit.lib.git")

local M = {}
M.__index = M

local function label(item)
  return ("%-8s %-12s %-14s %s"):format(item.kind or "wip", item.oid or "", item.date or "", item.message or "")
end

function M.new(items)
  return setmetatable({
    items = items or git.wip.list(),
    buffer = nil,
  }, M)
end

function M:item_at_cursor()
  return self.items[vim.fn.line(".") - 3]
end

function M:render(buffer)
  buffer = buffer or self.buffer
  if not buffer then
    return
  end

  local title = "Neogit WIP Snapshots"
  local lines = { title, string.rep("=", #title), "" }
  if #self.items == 0 then
    table.insert(lines, "No WIP snapshots")
  else
    for _, item in ipairs(self.items) do
      table.insert(lines, label(item))
    end
  end

  buffer:set_buffer_option("modifiable", true)
  buffer:set_lines(0, -1, false, lines)
  buffer:set_buffer_option("modifiable", false)
end

function M:apply_selected()
  local item = self:item_at_cursor()
  if not item then
    notification.warn("No WIP snapshot selected")
    return
  end

  local ok, err = git.wip.apply(item)
  if not ok then
    notification.error("Failed to apply WIP snapshot: " .. (err or "unknown error"))
  end
end

function M:open(kind)
  self.buffer = Buffer.create {
    name = "NeogitWipSnapshots",
    filetype = "NeogitWipSnapshots",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["<cr>"] = function()
          self:apply_selected()
        end,
        ["a"] = function()
          self:apply_selected()
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
