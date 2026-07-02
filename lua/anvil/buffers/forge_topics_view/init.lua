local Buffer = require("anvil.lib.buffer")
local input = require("anvil.lib.input")

local M = {}
M.__index = M

local function topic_label(topic)
  local kind = topic.kind == "pullreq" and "PR" or topic.kind == "discussion" and "Disc" or "Issue"
  local unread = topic.unread and "U" or " "
  local saved = topic.saved and "S" or " "
  local done = topic.done and "D" or " "
  return ("%s%s%s %-5s #%s %-8s %s"):format(
    unread,
    saved,
    done,
    kind,
    topic.number or "?",
    topic.state or "",
    topic.title or ""
  )
end

-- Forge tablist-style sort columns, cycled with `s`. Each entry knows how to
-- extract a comparable key and whether it defaults to descending order.
M.SORT_ORDER = {
  { key = "number", label = "number", desc = true },
  { key = "updated", label = "updated", desc = true },
  { key = "state", label = "state", desc = false },
  { key = "title", label = "title", desc = false },
}

function M.new(topics, title)
  return setmetatable({
    topics = topics or {},
    title = title or "Forge Topics",
    filter = "active",
    metadata_filter = nil,
    sort_index = 1,
    sort_reversed = false,
    buffer = nil,
  }, M)
end

---@param topic table
---@param key string
---@return number|string
local function sort_value(topic, key)
  if key == "number" then
    return tonumber(topic.number) or 0
  elseif key == "updated" then
    return tostring(topic.updated_at or "")
  elseif key == "state" then
    return tostring(topic.state or "")
  else
    return tostring(topic.title or ""):lower()
  end
end

local function names_include(items, needle)
  if not needle or needle == "" then
    return true
  end

  for _, item in ipairs(items or {}) do
    local name = type(item) == "table" and (item.name or item.login or item.slug) or item
    if tostring(name or "") == needle then
      return true
    end
  end

  return false
end

function M:filtered_topics()
  return vim.tbl_filter(function(topic)
    if self.filter == "unread" then
      return topic.unread
    elseif self.filter == "saved" then
      return topic.saved
    elseif self.filter == "done" then
      return topic.done
    elseif self.filter == "open" then
      return topic.state == "OPEN"
    elseif self.filter == "closed" then
      return topic.state == "CLOSED" or topic.state == "MERGED"
    elseif self.filter == "active" then
      return not topic.done
    end

    local metadata = self.metadata_filter
    if metadata and metadata.kind == "author" then
      return topic.author == metadata.value
    elseif metadata and metadata.kind == "label" then
      return names_include(topic.labels, metadata.value)
    elseif metadata and metadata.kind == "assignee" then
      return names_include(topic.assignees, metadata.value)
    elseif metadata and metadata.kind == "milestone" then
      return topic.milestone == metadata.value
    end

    return true
  end, self.topics)
end

---Returns the filtered topics sorted by the active tablist column.
---@return table[]
function M:sorted_topics()
  local topics = self:filtered_topics()
  local column = M.SORT_ORDER[self.sort_index]
  local descending = column.desc
  if self.sort_reversed then
    descending = not descending
  end

  table.sort(topics, function(a, b)
    local va, vb = sort_value(a, column.key), sort_value(b, column.key)
    if va == vb then
      -- Stable tiebreak on number so equal keys keep a deterministic order.
      va, vb = tonumber(a.number) or 0, tonumber(b.number) or 0
    end
    if descending then
      return va > vb
    end
    return va < vb
  end)

  return topics
end

---Human-readable description of the active sort, for the header.
---@return string
function M:sort_label()
  local column = M.SORT_ORDER[self.sort_index]
  local descending = column.desc
  if self.sort_reversed then
    descending = not descending
  end
  return ("%s %s"):format(column.label, descending and "v" or "^")
end

---Cycles to the next tablist sort column (magit/forge tablist columns).
function M:cycle_sort()
  self.sort_index = (self.sort_index % #M.SORT_ORDER) + 1
  self.sort_reversed = false
  self:render()
end

---Reverses the current sort direction.
function M:reverse_sort()
  self.sort_reversed = not self.sort_reversed
  self:render()
end

function M:set_filter(filter, metadata)
  self.filter = filter
  self.metadata_filter = metadata
  self:render()
end

function M:prompt_metadata_filter(kind, prompt)
  local value = input.get_user_input(prompt)
  if not value or value == "" then
    return
  end

  self:set_filter(kind, { kind = kind, value = value })
end

function M:open(kind)
  self.buffer = Buffer.create {
    name = "AnvilForgeTopics",
    filetype = "AnvilForgeTopics",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["<cr>"] = function()
          local topic = self:sorted_topics()[vim.fn.line(".") - 4]
          if topic then
            require("anvil.buffers.forge_topic_view").new(topic):open()
          end
        end,
        ["o"] = function()
          local topic = self:sorted_topics()[vim.fn.line(".") - 4]
          if topic and topic.url and vim.ui.open then
            vim.ui.open(topic.url)
          end
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
        ["O"] = function()
          self:set_filter("open")
        end,
        ["C"] = function()
          self:set_filter("closed")
        end,
        ["a"] = function()
          self:prompt_metadata_filter("author", "Author")
        end,
        ["r"] = function()
          self:prompt_metadata_filter("assignee", "Assignee")
        end,
        ["l"] = function()
          self:prompt_metadata_filter("label", "Label")
        end,
        ["m"] = function()
          self:prompt_metadata_filter("milestone", "Milestone")
        end,
        ["s"] = function()
          self:cycle_sort()
        end,
        ["i"] = function()
          self:reverse_sort()
        end,
        ["g"] = function()
          self:render()
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

function M:render(buffer)
  buffer = buffer or self.buffer
  if not buffer then
    return
  end

  local filter_label = self.filter
  if self.metadata_filter then
    filter_label = ("%s:%s"):format(self.metadata_filter.kind, self.metadata_filter.value)
  end

  local lines = {
    self.title,
    string.rep("=", #self.title),
    ("Filter: %s  Sort: %s"):format(filter_label, self:sort_label()),
    "",
  }
  for _, topic in ipairs(self:sorted_topics()) do
    table.insert(lines, topic_label(topic))
  end

  buffer:set_buffer_option("modifiable", true)
  buffer:set_lines(0, -1, false, lines)
  buffer:set_buffer_option("modifiable", false)
end

return M
