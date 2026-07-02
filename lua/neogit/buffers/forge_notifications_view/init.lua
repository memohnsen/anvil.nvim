local Buffer = require("neogit.lib.buffer")
local notification = require("neogit.lib.notification")

local M = {}
M.__index = M

local function label(item)
  local unread = item.unread and "*" or " "
  local saved = item.saved and "S" or " "
  local done = item.done and "D" or " "
  return ("%s%s%s %-16s %-22s %s"):format(unread, saved, done, item.reason or "", item.repository or "", item.title or "")
end

local FILTER_LABELS = {
  active = "active",
  all = "all",
  unread = "unread",
  saved = "saved",
  done = "done",
}

local function visible(items, filter)
  filter = filter or "active"

  return vim.tbl_filter(function(item)
    if filter == "all" then
      return true
    elseif filter == "unread" then
      return item.unread
    elseif filter == "saved" then
      return item.saved
    elseif filter == "done" then
      return item.done
    end

    return not item.done
  end, items)
end

function M.new(notifications)
  return setmetatable({
    notifications = notifications or {},
    filter = "active",
    visible_notifications = visible(notifications or {}, "active"),
    buffer = nil,
  }, M)
end

function M:item_at_cursor()
  return self.visible_notifications[vim.fn.line(".") - 4]
end

function M:replace_item(updated)
  for i, item in ipairs(self.notifications) do
    if tostring(item.id) == tostring(updated.id) then
      self.notifications[i] = vim.tbl_deep_extend("force", item, updated)
      self.visible_notifications = visible(self.notifications, self.filter)
      return
    end
  end

  table.insert(self.notifications, updated)
  self.visible_notifications = visible(self.notifications, self.filter)
end

function M:set_filter(filter)
  self.filter = filter
  self.visible_notifications = visible(self.notifications, self.filter)
  self:render()
end

function M:refresh()
  notification.info("Pulling forge notifications...")
  require("neogit.forge").pull_notifications(function(success, err)
    if not success then
      notification.error("Forge: failed to pull notifications: " .. (err or "unknown error"))
      return
    end

    local topics = require("neogit.forge").topics()
    self.notifications = topics.notifications or self.notifications
    self.visible_notifications = visible(self.notifications, self.filter)
    self:render()
    notification.info("Pulling forge notifications...done")
  end)
end

function M:render(buffer)
  buffer = buffer or self.buffer
  if not buffer then
    return
  end

  local title = "Forge Notifications"
  local lines = { title, string.rep("=", #title), ("Filter: %s"):format(FILTER_LABELS[self.filter] or self.filter), "" }
  for _, item in ipairs(self.visible_notifications) do
    table.insert(lines, label(item))
  end

  buffer:set_buffer_option("modifiable", true)
  buffer:set_lines(0, -1, false, lines)
  buffer:set_buffer_option("modifiable", false)
end

function M:with_item(action, success_message)
  local item = self:item_at_cursor()
  if not item then
    return
  end

  action(item, function(success, err)
    if not success then
      notification.error("Forge: failed to update notification: " .. (err or "unknown error"))
      return
    end

    local topics = require("neogit.forge").topics()
    self.notifications = topics.notifications or self.notifications
    self.visible_notifications = visible(self.notifications, self.filter)
    self:render()
    notification.info(success_message)
  end)
end

function M:open(kind)
  self.buffer = Buffer.create {
    name = "NeogitForgeNotifications",
    filetype = "NeogitForgeNotifications",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["o"] = function()
          local item = self:item_at_cursor()
          local url = item and (item.latest_comment_url or item.url)
          if url and vim.ui.open then
            vim.ui.open(url)
          end
        end,
        ["r"] = function()
          self:with_item(require("neogit.forge").mark_notification_read, "Notification marked read")
        end,
        ["u"] = function()
          self:with_item(require("neogit.forge").mark_notification_unread, "Notification marked unread")
        end,
        ["s"] = function()
          self:with_item(function(item, cb)
            require("neogit.forge").save_notification(item, not item.saved, cb)
          end, "Notification saved state updated")
        end,
        ["d"] = function()
          self:with_item(require("neogit.forge").done_notification, "Notification marked done")
        end,
        ["g"] = function()
          self:refresh()
        end,
        ["A"] = function()
          self:set_filter("all")
        end,
        ["U"] = function()
          self:set_filter("unread")
        end,
        ["S"] = function()
          self:set_filter("saved")
        end,
        ["D"] = function()
          self:set_filter("done")
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
