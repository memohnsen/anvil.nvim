-- Diffview-backed PR review flow (PLAN.md §2.6).
--
-- Bridges the pending-review-comment queue in `anvil.forge` to a diffview diff
-- of a pull request, so a reviewer can browse the PR diff and queue inline
-- comments on the line under the cursor with the correct file path and
-- LEFT/RIGHT side, the way octo's review engine does.

local M = {}

local api = vim.api

---Tracks the pull request currently being reviewed, so comment/submit actions
---know which topic to attach to.
---@type table|nil
local current_topic = nil

local function forge()
  return require("anvil.forge")
end

local function notify()
  return require("anvil.lib.notification")
end

local function diff_integration()
  local config = require("anvil.config")
  if config.get_diff_viewer() == "codediff" then
    return require("anvil.integrations.codediff")
  end
  return require("anvil.integrations.diffview")
end

---Sets the pull request under review.
---@param topic table|nil
function M.set_topic(topic)
  current_topic = topic
end

---@return table|nil
function M.get_topic()
  return current_topic
end

---Resolves which review side (LEFT = base/old, RIGHT = head/new) a window
---belongs to within a diffview layout. Pure so it can be unit tested against a
---mock layout.
---@param layout table|nil A diffview layout exposing `.a`/`.b` window handles
---@param winid integer
---@return string|nil "LEFT", "RIGHT", or nil when the window isn't a diff window
function M.side_for_window(layout, winid)
  if not layout then
    return nil
  end

  local a_win = layout.a and (layout.a.id or layout.a.winid)
  local b_win = layout.b and (layout.b.id or layout.b.winid)

  if a_win and winid == a_win then
    return "LEFT"
  end
  if b_win and winid == b_win then
    return "RIGHT"
  end

  return nil
end

---Builds a pending-comment target ({path, line, side}) from a diffview view and
---the cursor position. Pure so it can be unit tested with a mock view.
---@param view table|nil A diffview view exposing `.cur_entry` and `.cur_layout`
---@param winid integer
---@param line integer 1-based line under the cursor
---@return table|nil target
---@return string|nil error
function M.target_from_view(view, winid, line)
  if not view then
    return nil, "no diff is open"
  end

  local entry = view.cur_entry
  if not entry then
    return nil, "no file under review"
  end

  local side = M.side_for_window(view.cur_layout, winid) or "RIGHT"
  -- On the LEFT (base) side, comments attach to the pre-image path when the
  -- file was renamed; fall back to the current path otherwise.
  local path = (side == "LEFT" and (entry.oldpath or entry.path)) or entry.path
  if not path or path == "" then
    return nil, "no file path for the current diff line"
  end

  return { path = path, line = line, side = side }, nil
end

---@return table|nil view
local function current_diff_view()
  local ok, dv_lib = pcall(require, "diffview.lib")
  if not ok then
    return nil
  end

  local view
  pcall(function()
    view = dv_lib.get_current_view()
  end)
  return view
end

---Starts reviewing a pull request: records it as the active review topic and
---opens its base...head diff in the configured diff viewer.
---@param topic table
---@return boolean
function M.start(topic)
  if not topic or topic.kind ~= "pullreq" then
    notify().warn("Forge: select a pull request to review")
    return false
  end

  if not topic.base or not topic.head then
    notify().warn("Forge: pull request is missing base/head refs; pull forge topics first")
    return false
  end

  M.set_topic(topic)
  diff_integration().open("range", ("%s...%s"):format(topic.base, topic.head))
  notify().info(("Reviewing #%d — queue comments with the review comment mapping"):format(topic.number))
  return true
end

---Queues a pending review comment on the diff line under the cursor.
---@param body string
---@return boolean
---@return string|nil error
function M.comment_at_cursor(body)
  local topic = current_topic
  if not topic then
    return false, "no pull request is being reviewed"
  end

  if not body or body == "" then
    return false, "empty comment"
  end

  local winid = api.nvim_get_current_win()
  local line = api.nvim_win_get_cursor(winid)[1]
  local target, err = M.target_from_view(current_diff_view(), winid, line)
  if not target then
    return false, err
  end

  target.body = body
  return forge().add_pending_review_comment(topic, target)
end

---Submits the queued review for the active topic.
---@param event string COMMENT | APPROVE | REQUEST_CHANGES
---@param body string|nil
---@param cb fun(success: boolean, err: string|nil)|nil
function M.submit(event, body, cb)
  cb = cb or function() end
  local topic = current_topic
  if not topic then
    cb(false, "no pull request is being reviewed")
    return
  end

  forge().submit_pullreq_review(topic, event, body, function(success, err)
    if success then
      M.set_topic(nil)
    end
    cb(success, err)
  end)
end

return M
