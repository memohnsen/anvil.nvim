local Buffer = require("anvil.lib.buffer")
local notification = require("anvil.lib.notification")

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
    grouped = false,
    -- Maps a rendered (1-based) buffer line to its notification, so cursor
    -- lookups stay correct in both the flat and repository-grouped styles.
    line_items = {},
    visible_notifications = visible(notifications or {}, "active"),
    buffer = nil,
  }, M)
end

function M:item_at_cursor()
  return self.line_items[vim.fn.line(".")]
end

---Toggles between the flat list and forge's repository-grouped (nested) style.
function M:toggle_grouping()
  self.grouped = not self.grouped
  self:render()
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
  require("anvil.forge").pull_notifications(function(success, err)
    if not success then
      notification.error("Forge: failed to pull notifications: " .. (err or "unknown error"))
      return
    end

    local topics = require("anvil.forge").topics()
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
  local style = self.grouped and "grouped" or "flat"
  local lines = {
    title,
    string.rep("=", #title),
    ("Filter: %s  Style: %s"):format(FILTER_LABELS[self.filter] or self.filter, style),
    "",
  }

  self.line_items = {}

  if self.grouped then
    -- Preserve first-seen repository order, listing each repo's notifications
    -- under a header (forge's nested notification style).
    local order = {}
    local by_repo = {}
    for _, item in ipairs(self.visible_notifications) do
      local repo = item.repository or "(unknown)"
      if not by_repo[repo] then
        by_repo[repo] = {}
        table.insert(order, repo)
      end
      table.insert(by_repo[repo], item)
    end

    for _, repo in ipairs(order) do
      table.insert(lines, repo)
      for _, item in ipairs(by_repo[repo]) do
        table.insert(lines, "  " .. label(item))
        self.line_items[#lines] = item
      end
    end
  else
    for _, item in ipairs(self.visible_notifications) do
      table.insert(lines, label(item))
      self.line_items[#lines] = item
    end
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

    local topics = require("anvil.forge").topics()
    self.notifications = topics.notifications or self.notifications
    self.visible_notifications = visible(self.notifications, self.filter)
    self:render()
    notification.info(success_message)
  end)
end

function M:open(kind)
  self.buffer = Buffer.create {
    name = "AnvilForgeNotifications",
    filetype = "AnvilForgeNotifications",
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
          self:with_item(require("anvil.forge").mark_notification_read, "Notification marked read")
        end,
        ["u"] = function()
          self:with_item(require("anvil.forge").mark_notification_unread, "Notification marked unread")
        end,
        ["s"] = function()
          self:with_item(function(item, cb)
            require("anvil.forge").save_notification(item, not item.saved, cb)
          end, "Notification saved state updated")
        end,
        ["d"] = function()
          self:with_item(require("anvil.forge").done_notification, "Notification marked done")
        end,
        ["g"] = function()
          self:refresh()
        end,
        ["t"] = function()
          self:toggle_grouping()
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
