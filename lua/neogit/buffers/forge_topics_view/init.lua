local Buffer = require("neogit.lib.buffer")
local input = require("neogit.lib.input")

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

function M.new(topics, title)
  return setmetatable({
    topics = topics or {},
    title = title or "Forge Topics",
    filter = "active",
    metadata_filter = nil,
    buffer = nil,
  }, M)
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
    name = "NeogitForgeTopics",
    filetype = "NeogitForgeTopics",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["<cr>"] = function()
          local topic = self:filtered_topics()[vim.fn.line(".") - 4]
          if topic then
            require("neogit.buffers.forge_topic_view").new(topic):open()
          end
        end,
        ["o"] = function()
          local topic = self:filtered_topics()[vim.fn.line(".") - 4]
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

  local lines = { self.title, string.rep("=", #self.title), ("Filter: %s"):format(filter_label), "" }
  for _, topic in ipairs(self:filtered_topics()) do
    table.insert(lines, topic_label(topic))
  end

  buffer:set_buffer_option("modifiable", true)
  buffer:set_lines(0, -1, false, lines)
  buffer:set_buffer_option("modifiable", false)
end

return M
