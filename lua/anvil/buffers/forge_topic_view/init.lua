local Buffer = require("anvil.lib.buffer")
local notification = require("anvil.lib.notification")
local input = require("anvil.lib.input")
local suggestions = require("anvil.forge.suggestions")
local forge = require("anvil.forge")

local M = {}
M.__index = M

local function join_names(items)
  if type(items) ~= "table" or #items == 0 then
    return "-"
  end

  local names = {}
  for _, item in ipairs(items) do
    if type(item) == "table" then
      table.insert(names, item.name or item.login or vim.inspect(item))
    else
      table.insert(names, tostring(item))
    end
  end

  return table.concat(names, ", ")
end

local REACTION_LABELS = {
  THUMBS_UP = "+1",
  THUMBS_DOWN = "-1",
  LAUGH = "laugh",
  CONFUSED = "confused",
  HEART = "heart",
  HOORAY = "hooray",
  ROCKET = "rocket",
  EYES = "eyes",
}

local function reaction_summary(items)
  if type(items) ~= "table" or #items == 0 then
    return "-"
  end

  local reactions = {}
  for _, item in ipairs(items) do
    local count = tonumber(item.count) or 0
    if count > 0 then
      table.insert(reactions, ("%s %d"):format(REACTION_LABELS[item.content] or item.content, count))
    end
  end

  if #reactions == 0 then
    return "-"
  end

  return table.concat(reactions, ", ")
end

-- A tiny render builder that accumulates lines together with byte-column
-- highlight spans, so the topic buffer can be styled instead of plain text.
local Builder = {}
Builder.__index = Builder

function Builder.new()
  return setmetatable({ lines = {}, highlights = {} }, Builder)
end

--- Append a line built from segments. A segment is either a plain string or a
--- `{ text, hl }` table; when `hl` is set, that span is highlighted.
---@param segments string|table
function Builder:add(segments)
  if type(segments) == "string" then
    segments = { { text = segments } }
  elseif segments.text then
    segments = { segments }
  end

  local row = #self.lines
  local text = ""
  for _, seg in ipairs(segments) do
    local piece = seg.text or ""
    local col_start = #text
    text = text .. piece
    if seg.hl and piece ~= "" then
      table.insert(self.highlights, { row, col_start, #text, seg.hl })
    end
  end

  table.insert(self.lines, text)
end

function Builder:blank()
  table.insert(self.lines, "")
end

--- A section header rendered as a colored bar: "▌ Title (count)".
function Builder:section(title, count)
  local segments = {
    { text = "▌ ", hl = "AnvilSectionHeader" },
    { text = title, hl = "AnvilSectionHeader" },
  }
  if count ~= nil then
    table.insert(segments, { text = (" (%d)"):format(count), hl = "AnvilSectionHeaderCount" })
  end
  self:add(segments)
end

--- A "Label   value" metadata row with a subtle label and highlighted value.
function Builder:field(label, value, value_hl)
  self:add {
    { text = ("  %-11s"):format(label), hl = "AnvilSubtleText" },
    { text = value or "-", hl = value_hl },
  }
end

--- Wrap free-form body/comment text, indenting each line.
function Builder:body(text, indent)
  indent = indent or "  "
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    self:add(indent .. line)
  end
end

local STATE_HL = {
  OPEN = "AnvilGraphGreen",
  CLOSED = "AnvilGraphBoldRed",
  MERGED = "AnvilGraphPurple",
}

--- The compact keybinding hint block at the top of the buffer. Keys are
--- highlighted; descriptions are subtle. Pairs wrap to fit ~76 columns.
---@param builder table
---@param topic table
local function render_hints(builder, topic)
  local hints = {
    { "f", "refresh" },
    { "c", "comment" },
    { "e", "title" },
    { "b", "body" },
    { "l", "labels" },
    { "a", "assignees" },
    { "m", "milestone" },
    { "+", "react" },
    { "s", "open/close" },
    { "M", "read" },
    { "*", "save" },
    { "d", "done" },
    { "o", "open URL" },
    { "Y", "yank URL" },
    { "q", "close" },
  }

  if topic.kind == "pullreq" then
    vim.list_extend(hints, {
      { "r", "reviewers" },
      { "V", "review comment" },
      { "A", "approve" },
      { "v", "comment review" },
      { "X", "request changes" },
      { "i", "reply thread" },
      { "x", "resolve" },
      { "S", "apply suggestion" },
    })
  end

  local max_width = 76
  local segments = {}
  local width = 0

  local function flush()
    if #segments > 0 then
      builder:add(segments)
      segments = {}
      width = 0
    end
  end

  for _, hint in ipairs(hints) do
    local key, desc = hint[1], hint[2]
    local chunk = #key + 1 + #desc + 3
    if width > 0 and width + chunk > max_width then
      flush()
    end
    if width == 0 then
      table.insert(segments, { text = "  " })
      width = 2
    end
    table.insert(segments, { text = key, hl = "AnvilPopupSwitchKey" })
    table.insert(segments, { text = " " .. desc .. "   ", hl = "AnvilSubtleText" })
    width = width + chunk
  end
  flush()
end

local function build(topic)
  local builder = Builder.new()

  local kind = topic.kind == "pullreq" and "Pull request" or topic.kind == "discussion" and "Discussion" or "Issue"

  -- Title bar: "Issue #12  ●OPEN  @author"
  builder:add {
    { text = ("%s #%s"):format(kind, topic.number or "?"), hl = "AnvilPopupBold" },
    { text = "  " },
    { text = "● " .. (topic.state or "-"), hl = STATE_HL[topic.state] or "AnvilSubtleText" },
    { text = topic.author and ("  @" .. topic.author) or "", hl = "AnvilPopupBranchName" },
  }
  builder:add { { text = topic.title or "", hl = "AnvilPopupBold" } }
  builder:blank()

  render_hints(builder, topic)
  builder:blank()

  -- Details section.
  builder:section("Details")
  local marks = {}
  if topic.unread then
    table.insert(marks, "unread")
  end
  if topic.saved then
    table.insert(marks, "saved")
  end
  if topic.done then
    table.insert(marks, "done")
  end
  builder:field("Marks", #marks > 0 and table.concat(marks, ", ") or "-")
  builder:field("Updated", topic.updated_at or "-")
  builder:field("Labels", join_names(topic.labels), "AnvilTagName")
  builder:field("Assignees", join_names(topic.assignees))
  builder:field("Milestone", topic.milestone or "-")
  builder:field("Reactions", reaction_summary(topic.reactions))
  if topic.kind == "pullreq" then
    builder:field("Draft", topic.draft and "yes" or "no")
    builder:field("Head", topic.head or "-", "AnvilPopupBranchName")
    builder:field("Base", topic.base or "-", "AnvilPopupBranchName")
    builder:field("Review", topic.review_decision or "-")
    builder:field("Reviewers", join_names(topic.review_requests))
  end
  builder:field("URL", topic.url or "-", "AnvilFilePath")
  builder:blank()

  -- Description.
  builder:section("Description")
  if topic.body and topic.body ~= "" then
    builder:body(topic.body)
  else
    builder:add { { text = "  (no description)", hl = "AnvilSubtleText" } }
  end
  builder:blank()

  -- Comments.
  local comments = type(topic.comments) == "table" and topic.comments or {}
  builder:section("Comments", #comments)
  if #comments > 0 then
    for idx, comment in ipairs(comments) do
      builder:add {
        { text = ("  #%d "):format(idx), hl = "AnvilSubtleText" },
        { text = "@" .. (comment.author or "unknown"), hl = "AnvilPopupBranchName" },
        { text = "  " .. (comment.created_at or ""), hl = "AnvilSubtleText" },
      }
      local reactions = reaction_summary(comment.reactions)
      if reactions ~= "-" then
        builder:field("reactions", reactions)
      end
      if comment.body and comment.body ~= "" then
        builder:body(comment.body, "    ")
      end
      builder:blank()
    end
  else
    builder:add { { text = "  (no comments)", hl = "AnvilSubtleText" } }
    builder:blank()
  end

  if topic.kind == "pullreq" then
    local pending_comments = forge.pending_review_comments(topic)
    builder:section("Pending review comments", #pending_comments)
    if #pending_comments > 0 then
      for idx, comment in ipairs(pending_comments) do
        builder:add {
          { text = ("  #%d "):format(idx), hl = "AnvilSubtleText" },
          { text = ("%s:%s"):format(comment.path or "-", comment.line or "?"), hl = "AnvilFilePath" },
        }
        builder:body(comment.body or "", "    ")
      end
    else
      builder:add { { text = "  (none)", hl = "AnvilSubtleText" } }
    end
    builder:blank()

    local reviews = type(topic.reviews) == "table" and topic.reviews or {}
    builder:section("Reviews", #reviews)
    if #reviews > 0 then
      for _, review in ipairs(reviews) do
        builder:add {
          { text = "  @" .. (review.author or "unknown"), hl = "AnvilPopupBranchName" },
          { text = "  " .. (review.state or ""), hl = "AnvilPopupBold" },
          { text = "  " .. (review.submitted_at or ""), hl = "AnvilSubtleText" },
        }
        if review.body and review.body ~= "" then
          builder:body(review.body, "    ")
        end
        builder:blank()
      end
    else
      builder:add { { text = "  (no reviews)", hl = "AnvilSubtleText" } }
      builder:blank()
    end

    local threads = type(topic.review_threads) == "table" and topic.review_threads or {}
    builder:section("Review threads", #threads)
    if #threads > 0 then
      for idx, thread in ipairs(threads) do
        local status = thread.resolved and "resolved" or "unresolved"
        if thread.outdated then
          status = status .. ", outdated"
        end
        local line = thread.line or thread.start_line or "?"
        builder:add {
          { text = ("  #%d "):format(idx), hl = "AnvilSubtleText" },
          { text = ("%s:%s"):format(thread.path or "-", line), hl = "AnvilFilePath" },
          { text = (" (%s)"):format(status), hl = thread.resolved and "AnvilGraphGreen" or "AnvilSubtleText" },
        }

        for comment_idx, comment in ipairs(thread.comments or {}) do
          builder:add {
            { text = ("    %d.%d "):format(idx, comment_idx), hl = "AnvilSubtleText" },
            { text = "@" .. (comment.author or "unknown"), hl = "AnvilPopupBranchName" },
            { text = "  " .. (comment.created_at or ""), hl = "AnvilSubtleText" },
          }
          local reactions = reaction_summary(comment.reactions)
          if reactions ~= "-" then
            builder:field("reactions", reactions)
          end
          if comment.diff_hunk and comment.diff_hunk ~= "" then
            builder:add { { text = "      diff:", hl = "AnvilSubtleText" } }
            builder:body(comment.diff_hunk, "      ")
          end
          if comment.body and comment.body ~= "" then
            builder:body(comment.body, "      ")
            for suggestion_idx, _ in ipairs(suggestions.parse(comment.body)) do
              builder:add {
                { text = ("      suggestion %d.%d.%d "):format(idx, comment_idx, suggestion_idx), hl = "AnvilSubtleText" },
                {
                  text = ("%s:%s-%s"):format(
                    thread.path or "-",
                    thread.start_line or thread.line or "?",
                    thread.line or thread.start_line or "?"
                  ),
                  hl = "AnvilFilePath",
                },
              }
            end
          end
          builder:blank()
        end
      end
    else
      builder:add { { text = "  (no review threads)", hl = "AnvilSubtleText" } }
      builder:blank()
    end
  end

  builder:add { { text = ("Detail synced: %s"):format(topic.detail_synced_at or "not yet"), hl = "AnvilSubtleText" } }

  return builder
end

---@param topic table
---@return ForgeTopicViewBuffer
function M.new(topic)
  return setmetatable({
    topic = topic,
    buffer = nil,
    post_editor = nil,
  }, M)
end

function M:pull_detail(message)
  notification.info(message or "Pulling forge topic detail...")
  forge.pull_topic(self.topic, function(success, err, topic)
    if not success then
      notification.error("Forge: failed to pull topic detail: " .. (err or "unknown error"))
      return
    end

    self.topic = topic
    self:render()
    notification.info((message or "Pulling forge topic detail...") .. "done")
  end)
end

function M:comment()
  self.post_editor = require("anvil.buffers.forge_post_editor")
    .new {
      title = ("Comment on %s #%s"):format(self.topic.kind or "topic", self.topic.number or "?"),
      on_submit = function(body, done)
        forge.comment_topic(self.topic, body, function(success, err)
          if success then
            self:pull_detail("Forge comment posted; refreshing topic...")
          end
          done(success, err)
        end)
      end,
    }
    :open("split")
end

function M:add_reaction()
  local reaction = input.get_user_input("Reaction (+1, -1, laugh, confused, heart, hooray, rocket, eyes)", {
    default = "+1",
  })
  if not reaction or reaction == "" then
    return
  end

  forge.add_reaction(self.topic, reaction, function(success)
    if success then
      self:pull_detail("Forge reaction added; refreshing topic...")
    end
  end)
end

function M:add_reaction_to(subject, message)
  if not subject then
    return
  end

  if not subject.id then
    notification.warn("Forge: selected item has no reaction id. Pull fresh topic detail first.")
    return
  end

  local reaction = input.get_user_input("Reaction (+1, -1, laugh, confused, heart, hooray, rocket, eyes)", {
    default = "+1",
  })
  if not reaction or reaction == "" then
    return
  end

  forge.add_reaction(subject, reaction, function(success)
    if success then
      self:pull_detail(message)
    end
  end)
end

function M:select_comment()
  local comments = self.topic.comments or {}
  if #comments == 0 then
    notification.warn("Forge: no comments in this topic. Pull fresh topic detail first.")
    return nil
  end

  local idx = tonumber(input.get_user_input("Comment number", { default = "1" }))
  if not idx or not comments[idx] then
    notification.warn("Forge: invalid comment number")
    return nil
  end

  return comments[idx]
end

function M:add_comment_reaction()
  self:add_reaction_to(self:select_comment(), "Forge comment reaction added; refreshing topic...")
end

function M:edit_title()
  local title = input.get_user_input("Title", { default = self.topic.title or "" })
  if not title or title == "" then
    return
  end

  forge.edit_topic_title(self.topic, title, function(success)
    if success then
      self.topic.title = title
      self:render()
      self:pull_detail("Forge title updated; refreshing topic...")
    end
  end)
end

function M:edit_labels()
  local labels = input.get_user_input("Labels (comma-separated)")
  if not labels or labels == "" then
    return
  end

  forge.edit_topic_labels(self.topic, labels, function(success)
    if success then
      self:pull_detail("Forge labels updated; refreshing topic...")
    end
  end)
end

function M:edit_body()
  self.post_editor = require("anvil.buffers.forge_post_editor")
    .new {
      title = ("Edit %s #%s body"):format(self.topic.kind or "topic", self.topic.number or "?"),
      initial = self.topic.body or "",
      on_submit = function(body, done)
        forge.edit_topic_body(self.topic, body, function(success, err)
          if success then
            self.topic.body = body
            self:render()
            self:pull_detail("Forge body updated; refreshing topic...")
          end
          done(success, err)
        end)
      end,
    }
    :open("split")
end

function M:edit_assignees()
  local assignees = input.get_user_input("Assignees (comma-separated)", {
    default = join_names(self.topic.assignees),
  })
  if not assignees or assignees == "" or assignees == "-" then
    return
  end

  forge.edit_topic_assignees(self.topic, assignees, function(success)
    if success then
      self:pull_detail("Forge assignees updated; refreshing topic...")
    end
  end)
end

function M:edit_milestone()
  local milestone = input.get_user_input("Milestone", { default = self.topic.milestone or "" })
  if not milestone or milestone == "" then
    return
  end

  forge.edit_topic_milestone(self.topic, milestone, function(success)
    if success then
      self.topic.milestone = milestone
      self:render()
      self:pull_detail("Forge milestone updated; refreshing topic...")
    end
  end)
end

function M:add_reviewers()
  local reviewers = input.get_user_input("Reviewers (comma-separated)", {
    default = join_names(self.topic.review_requests),
  })
  if not reviewers or reviewers == "" or reviewers == "-" then
    return
  end

  forge.add_pullreq_reviewers(self.topic, reviewers, function(success)
    if success then
      self:pull_detail("Forge reviewers requested; refreshing topic...")
    end
  end)
end

function M:remove_reviewers()
  local reviewers = input.get_user_input("Remove reviewers (comma-separated)", {
    default = join_names(self.topic.review_requests),
  })
  if not reviewers or reviewers == "" or reviewers == "-" then
    return
  end

  forge.remove_pullreq_reviewers(self.topic, reviewers, function(success)
    if success then
      self:pull_detail("Forge reviewers removed; refreshing topic...")
    end
  end)
end

function M:select_review_thread()
  local threads = self.topic.review_threads or {}
  if #threads == 0 then
    notification.warn("Forge: no review threads in this topic. Pull fresh topic detail first.")
    return nil
  end

  local idx = tonumber(input.get_user_input("Review thread number", { default = "1" }))
  if not idx or not threads[idx] then
    notification.warn("Forge: invalid review thread number")
    return nil
  end

  return threads[idx]
end

function M:reply_review_thread()
  local thread = self:select_review_thread()
  if not thread then
    return
  end

  self.post_editor = require("anvil.buffers.forge_post_editor")
    .new {
      title = "Reply to review thread",
      on_submit = function(body, done)
        forge.reply_review_thread(thread, body, function(success, err)
          if success then
            self:pull_detail("Forge review-thread reply posted; refreshing topic...")
          end
          done(success, err)
        end)
      end,
    }
    :open("split")
end

function M:resolve_review_thread()
  local thread = self:select_review_thread()
  if not thread then
    return
  end

  forge.resolve_review_thread(thread, function(success)
    if success then
      thread.resolved = true
      self:render()
      self:pull_detail("Forge review thread resolved; refreshing topic...")
    end
  end)
end

function M:unresolve_review_thread()
  local thread = self:select_review_thread()
  if not thread then
    return
  end

  forge.unresolve_review_thread(thread, function(success)
    if success then
      thread.resolved = false
      self:render()
      self:pull_detail("Forge review thread unresolved; refreshing topic...")
    end
  end)
end

function M:select_review_thread_comment()
  local thread = self:select_review_thread()
  if not thread then
    return nil
  end

  local comments = thread.comments or {}
  if #comments == 0 then
    notification.warn("Forge: no comments in this review thread. Pull fresh topic detail first.")
    return nil
  end

  local idx = tonumber(input.get_user_input("Review thread comment number", { default = "1" }))
  if not idx or not comments[idx] then
    notification.warn("Forge: invalid review thread comment number")
    return nil
  end

  return comments[idx]
end

function M:add_review_thread_comment_reaction()
  self:add_reaction_to(self:select_review_thread_comment(), "Forge review-thread comment reaction added; refreshing topic...")
end

function M:select_suggested_change()
  local items = suggestions.collect(self.topic)
  if #items == 0 then
    notification.warn("Forge: no suggested changes in this topic. Pull fresh topic detail first.")
    return nil
  end

  local idx = tonumber(input.get_user_input("Suggested change number", { default = "1" }))
  if not idx or not items[idx] then
    notification.warn("Forge: invalid suggested change number")
    return nil
  end

  return items[idx]
end

function M:apply_suggested_change()
  local suggestion = self:select_suggested_change()
  if not suggestion then
    return
  end

  local root = require("anvil.lib.git").repo.worktree_root
  local ok, err = suggestions.apply(suggestion, root)
  if not ok then
    notification.error("Forge: failed to apply suggested change: " .. (err or "unknown error"))
  end
end

function M:add_pending_review_comment()
  if self.topic.kind ~= "pullreq" then
    notification.warn("Forge: reviews are only available for pull requests")
    return
  end

  local path = input.get_user_input("Review file path")
  if not path or path == "" then
    return
  end

  local line = input.get_user_input("Review line", { default = "1" })
  if not tonumber(line) then
    notification.warn("Forge: invalid review line")
    return
  end

  self.post_editor = require("anvil.buffers.forge_post_editor")
    .new {
      title = ("Review comment on %s:%s"):format(path, line),
      on_submit = function(body, done)
        local ok, err = forge.add_pending_review_comment(self.topic, {
          path = path,
          line = line,
          body = body,
        })

        if ok then
          self:render()
        end

        done(ok, err)
      end,
    }
    :open("split")
end

---@param event_name string
function M:submit_review(event_name)
  if self.topic.kind ~= "pullreq" then
    notification.warn("Forge: reviews are only available for pull requests")
    return
  end

  local labels = {
    APPROVE = "Approve pull request",
    COMMENT = "Comment on pull request",
    REQUEST_CHANGES = "Request changes",
  }
  local normalized = event_name:gsub("-", "_"):upper()

  self.post_editor = require("anvil.buffers.forge_post_editor")
    .new {
      title = labels[normalized] or "Submit pull request review",
      on_submit = function(body, done)
        forge.submit_pullreq_review(self.topic, normalized, body, function(success, err)
          if success then
            self:pull_detail("Forge review submitted; refreshing topic...")
          end

          done(success, err)
        end)
      end,
    }
    :open("split")
end

function M:mark_read()
  forge.mark_topic_read(self.topic, function(success)
    if success then
      self.topic.unread = false
      self.topic.done = false
      self:render()
    end
  end)
end

function M:mark_unread()
  forge.mark_topic_unread(self.topic, function(success)
    if success then
      self.topic.unread = true
      self.topic.done = false
      self:render()
    end
  end)
end

function M:toggle_saved()
  local saved = not self.topic.saved
  forge.save_topic_mark(self.topic, saved, function(success)
    if success then
      self.topic.saved = saved
      self.topic.done = false
      self:render()
    end
  end)
end

function M:mark_done()
  forge.mark_topic_done(self.topic, function(success)
    if success then
      self.topic.done = true
      self.topic.unread = false
      self:render()
    end
  end)
end

function M:toggle_state()
  forge.toggle_topic_state(self.topic, function(success)
    if success then
      self.topic.state = self.topic.state == "OPEN" and "CLOSED" or "OPEN"
      self:render()
      self:pull_detail("Forge topic state updated; refreshing topic...")
    end
  end)
end

---@param kind string|nil
---@return ForgeTopicViewBuffer
function M:open(kind)
  local name = ("AnvilForgeTopic://%s/%s"):format(self.topic.kind or "topic", self.topic.number or "unknown")

  self.buffer = Buffer.create {
    name = name,
    filetype = "AnvilForgeTopic",
    kind = kind or "replace",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["q"] = function(buffer)
          buffer:close()
        end,
        ["<esc>"] = function(buffer)
          buffer:close()
        end,
        ["o"] = function()
          if self.topic.url and vim.ui.open then
            vim.ui.open(self.topic.url)
          end
        end,
        ["Y"] = function()
          if self.topic.url then
            vim.fn.setreg("+", self.topic.url)
          end
        end,
        ["M"] = function()
          self:mark_read()
        end,
        ["u"] = function()
          self:mark_unread()
        end,
        ["*"] = function()
          self:toggle_saved()
        end,
        ["d"] = function()
          self:mark_done()
        end,
        ["c"] = function()
          self:comment()
        end,
        ["+"] = function()
          self:add_reaction()
        end,
        ["C"] = function()
          self:add_comment_reaction()
        end,
        ["e"] = function()
          self:edit_title()
        end,
        ["l"] = function()
          self:edit_labels()
        end,
        ["b"] = function()
          self:edit_body()
        end,
        ["a"] = function()
          self:edit_assignees()
        end,
        ["m"] = function()
          self:edit_milestone()
        end,
        ["r"] = function()
          self:add_reviewers()
        end,
        ["R"] = function()
          self:remove_reviewers()
        end,
        ["V"] = function()
          self:add_pending_review_comment()
        end,
        ["A"] = function()
          self:submit_review("APPROVE")
        end,
        ["v"] = function()
          self:submit_review("COMMENT")
        end,
        ["X"] = function()
          self:submit_review("REQUEST_CHANGES")
        end,
        ["i"] = function()
          self:reply_review_thread()
        end,
        ["I"] = function()
          self:add_review_thread_comment_reaction()
        end,
        ["S"] = function()
          self:apply_suggested_change()
        end,
        ["x"] = function()
          self:resolve_review_thread()
        end,
        ["U"] = function()
          self:unresolve_review_thread()
        end,
        ["s"] = function()
          self:toggle_state()
        end,
        ["f"] = function()
          self:pull_detail()
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

  local builder = build(self.topic)

  buffer:set_buffer_option("modifiable", true)
  -- Clear directly (not via clear_namespace, which no-ops when unfocused, e.g.
  -- when an async detail pull re-renders a background buffer).
  local ns_id = buffer:get_namespace_id("default")
  if ns_id then
    vim.api.nvim_buf_clear_namespace(buffer.handle, ns_id, 0, -1)
  end
  buffer:set_lines(0, -1, false, builder.lines)
  for _, hl in ipairs(builder.highlights) do
    local row, col_start, col_end, group = hl[1], hl[2], hl[3], hl[4]
    buffer:add_highlight(row, col_start, col_end, group)
  end
  buffer:set_buffer_option("modifiable", false)
end

return M
