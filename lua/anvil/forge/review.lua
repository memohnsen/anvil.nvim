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

---@param help_mapping string|nil
---@return string
function M.file_panel_help_hint(help_mapping)
  return (help_mapping or "g?") .. " • V: Viewed • q: Anvil"
end

---@param buffer integer|nil
---@param view table
local function map_review_buffer(buffer, view)
  if not buffer or not api.nvim_buf_is_valid(buffer) then
    return
  end

  vim.keymap.set("n", "V", function()
    M.mark_current_file_viewed(function(success, err)
      if success then
        notify().info("Forge: marked file as viewed")
      else
        notify().error("Forge: " .. (err or "failed to mark file as viewed"))
      end
    end)
  end, { buffer = buffer, silent = true, nowait = true, desc = "Mark file viewed" })

  vim.keymap.set("n", "q", function()
    view:close()
  end, { buffer = buffer, silent = true, nowait = true, desc = "Return to Anvil" })
end

---@param view table|nil
local function add_review_mappings(view)
  local panel = view and view.panel
  if not panel or not panel.bufid or not api.nvim_buf_is_valid(panel.bufid) then
    return
  end

  map_review_buffer(panel.bufid, view)
  for _, side in ipairs({ "a", "b", "c", "d" }) do
    local file = view.cur_layout and view.cur_layout[side] and view.cur_layout[side].file
    map_review_buffer(file and file.bufnr, view)
  end

  if not panel.anvil_review_help_configured then
    panel.help_mapping = M.file_panel_help_hint(panel.help_mapping)
    panel.anvil_review_help_configured = true
    panel:render()
    panel:redraw()
  end
end

---Removes a reviewed entry from Diffview's current file list and selects the
---next remaining file. Kept separate from the GitHub mutation for testability.
---@param view table
---@param entry table
---@return boolean
function M.hide_reviewed_file(view, entry)
  if not view or not entry or not view.files or not view.panel then
    return false
  end

  local files = view.files
  local panel = view.panel
  local ordered = panel.ordered_file_list and panel:ordered_file_list() or {}
  local index
  for i, file in ipairs(ordered) do
    if file == entry then
      index = i
      break
    end
  end

  local replacement
  if index and #ordered > 1 then
    replacement = ordered[(index % #ordered) + 1]
  end

  local removed = false
  for _, kind in ipairs({ "conflicting", "working", "staged" }) do
    local entries = files[kind]
    if entries then
      for i, file in ipairs(entries) do
        if file == entry then
          table.remove(entries, i)
          removed = true
          break
        end
      end
    end
    if removed then
      break
    end
  end

  if not removed then
    return false
  end

  if not replacement then
    if panel.set_cur_file then
      panel:set_cur_file(nil)
    end
    if view.cur_entry == entry then
      if entry.layout and entry.layout.detach_files then
        entry.layout:detach_files()
      end
      view.cur_entry = nil
    end
  end

  if entry.destroy then
    entry:destroy()
  end
  if files.update_file_trees then
    files:update_file_trees()
  end
  if panel.update_components then
    panel:update_components()
  end
  if panel.render then
    panel:render()
  end
  if panel.redraw then
    panel:redraw()
  end
  if panel.reconstrain_cursor then
    panel:reconstrain_cursor()
  end

  if replacement and panel.set_cur_file and view.set_file then
    panel:set_cur_file(replacement)
    view:set_file(replacement, true, true)
  elseif view.file_safeguard then
    view:file_safeguard()
  end

  return true
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
  local view = diff_integration().open("range", ("%s...%s"):format(topic.base, topic.head))
  if view then
    vim.schedule(function()
      add_review_mappings(view)
      view.emitter:on("file_open_post", function()
        add_review_mappings(view)
      end)
    end)
  end
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

---Marks the current Diffview file as viewed on GitHub and removes it from the
---review tree after GitHub accepts the update.
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_current_file_viewed(cb)
  cb = cb or function() end
  if not current_topic then
    cb(false, "no pull request is being reviewed")
    return
  end

  local view = current_diff_view()
  local entry = view and view.cur_entry
  if not entry or not entry.path or entry.path == "" then
    cb(false, "no file under review")
    return
  end

  forge().mark_pullreq_file_viewed(current_topic, entry.path, function(success, err)
    if not success then
      cb(false, err)
      return
    end

    M.hide_reviewed_file(view, entry)
    cb(true, nil)
  end)
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
