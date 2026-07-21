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
  return (help_mapping or "g?") .. " • V: Viewed • X: Unview • q: Anvil"
end

---True while the Diffview file panel buffer is still alive. The GitHub
---mutations are async, so the view can disappear between request and response.
---@param view table|nil
---@return boolean
local function view_is_open(view)
  local panel = view and view.panel
  return (panel and panel.bufid and api.nvim_buf_is_valid(panel.bufid)) == true
end

---Maps the review file controls in the Diffview file panel. The panel only —
---mapping `V`/`q` in the diff file buffers would shadow Visual Line mode and
---macro recording where users actually need them.
---@param view table|nil
local function add_review_mappings(view)
  if not view_is_open(view) then
    return
  end

  local panel = view.panel
  local buffer = panel.bufid

  vim.keymap.set("n", "V", function()
    M.mark_current_file_viewed(function(success, err)
      if not success then
        notify().error("Forge: " .. (err or "failed to mark file as viewed"))
      elseif err then
        notify().warn("Forge: " .. err)
      else
        notify().info("Forge: marked file as viewed")
      end
    end)
  end, { buffer = buffer, silent = true, nowait = true, desc = "Mark file viewed" })

  vim.keymap.set("n", "X", function()
    M.unmark_last_viewed_file(function(success, err)
      if not success then
        notify().error("Forge: " .. (err or "failed to unmark file as viewed"))
      elseif err then
        notify().warn("Forge: " .. err)
      else
        notify().info("Forge: unmarked last viewed file")
      end
    end)
  end, { buffer = buffer, silent = true, nowait = true, desc = "Unmark last viewed file" })

  vim.keymap.set("n", "q", function()
    view:close()
  end, { buffer = buffer, silent = true, nowait = true, desc = "Return to Anvil" })

  if not panel.anvil_review_help_configured then
    panel.help_mapping = M.file_panel_help_hint(panel.help_mapping)
    panel.anvil_review_help_configured = true
    panel:render()
    panel:redraw()
  end
end

---Removes a reviewed entry from Diffview's current file list and selects the
---next remaining file. Kept separate from the GitHub mutation for testability.
---Only mutates this view's in-memory file list; `apply_viewed_paths` re-hides
---entries when Diffview rebuilds the list on refresh.
---@param view table
---@param entry table
---@param opts { keep_entry: boolean|nil, quiet: boolean|nil }|nil keep_entry skips `entry:destroy()` so the entry can be restored later; quiet skips selecting a replacement file (for bulk hides)
---@return boolean removed
---@return { kind: string, index: integer }|nil position where the entry sat, for `restore_hidden_file`
function M.hide_reviewed_file(view, entry, opts)
  opts = opts or {}
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
  if not opts.quiet and index and #ordered > 1 then
    replacement = ordered[(index % #ordered) + 1]
  end

  local position
  for _, kind in ipairs({ "conflicting", "working", "staged" }) do
    local entries = files[kind]
    if entries then
      for i, file in ipairs(entries) do
        if file == entry then
          table.remove(entries, i)
          position = { kind = kind, index = i }
          break
        end
      end
    end
    if position then
      break
    end
  end

  if not position then
    return false
  end

  if not replacement and view.cur_entry == entry then
    if panel.set_cur_file then
      panel:set_cur_file(nil)
    end
    if entry.layout and entry.layout.detach_files then
      entry.layout:detach_files()
    end
    view.cur_entry = nil
  end

  if entry.destroy and not opts.keep_entry then
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
  elseif not replacement and not opts.quiet and view.file_safeguard then
    view:file_safeguard()
  end

  return true, position
end

---Reinserts a previously hidden entry into the Diffview file list and selects
---it. Counterpart of `hide_reviewed_file` with `keep_entry` for un-viewing.
---@param view table
---@param entry table
---@param position { kind: string, index: integer }|nil original list position
---@return boolean
function M.restore_hidden_file(view, entry, position)
  if not view or not entry or not view.files or not view.panel then
    return false
  end

  local kind = position and position.kind or "working"
  local entries = view.files[kind]
  if not entries then
    return false
  end

  local index = math.min(position and position.index or (#entries + 1), #entries + 1)
  table.insert(entries, index, entry)

  local files = view.files
  local panel = view.panel
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

  if panel.set_cur_file and view.set_file then
    panel:set_cur_file(entry)
    view:set_file(entry, true, true)
  end

  return true
end

---Hides every file whose path the viewer has marked as viewed. Runs when the
---viewed state arrives from GitHub and again after Diffview rebuilds its file
---list (a refresh would otherwise resurrect hidden files).
---@param view table
function M.apply_viewed_paths(view)
  local paths = view and view.anvil_viewed_paths
  if not paths or not view_is_open(view) or not view.files then
    return
  end

  local matches = {}
  for _, kind in ipairs({ "conflicting", "working", "staged" }) do
    for _, entry in ipairs(view.files[kind] or {}) do
      if entry.path and paths[entry.path] then
        table.insert(matches, entry)
      end
    end
  end

  for _, entry in ipairs(matches) do
    M.hide_reviewed_file(view, entry, { quiet = true })
  end

  -- Quiet hides never pick a replacement; select one file at the end if the
  -- open entry was hidden.
  if #matches > 0 and not view.cur_entry and view.file_safeguard then
    view:file_safeguard()
  end
end

---Wires the review file controls into a Diffview view: panel mappings, the
---hidden-entry bookkeeping for viewed files, and the GitHub viewed-state sync.
---Safe to call repeatedly — Diffview reuses views, so everything beyond the
---(idempotent) mappings is attached exactly once per view.
---@param view table
---@param topic table
local function attach_review_view(view, topic)
  add_review_mappings(view)

  if view.anvil_review_attached then
    return
  end
  view.anvil_review_attached = true
  ---Stack of files marked viewed this session, newest last, for `X` restore.
  ---@type { entry: table, path: string, position: { kind: string, index: integer }|nil }[]
  view.anvil_hidden_entries = {}
  ---Set of paths the viewer has marked viewed (GitHub state + this session).
  ---@type table<string, boolean>
  view.anvil_viewed_paths = {}

  view.emitter:on("file_open_post", function()
    add_review_mappings(view)
  end)

  -- Diffview rebuilds its file list on refresh, which would resurrect hidden
  -- files; re-apply the hides after every update.
  view.emitter:on("files_updated", function()
    vim.schedule(function()
      M.apply_viewed_paths(view)
    end)
  end)

  -- Entries hidden with keep_entry were removed from Diffview's lists, so its
  -- own teardown misses them; destroy them when the view closes.
  view.emitter:on("view_closed", function()
    for _, hidden in ipairs(view.anvil_hidden_entries or {}) do
      if hidden.entry.destroy then
        pcall(hidden.entry.destroy, hidden.entry)
      end
    end
    view.anvil_hidden_entries = {}
  end)

  forge().pullreq_viewed_paths(topic, function(paths)
    if not paths or not view.anvil_viewed_paths then
      return
    end
    for _, path in ipairs(paths) do
      view.anvil_viewed_paths[path] = true
    end
    M.apply_viewed_paths(view)
  end)
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
      attach_review_view(view, topic)
    end)
  else
    -- codediff's integration doesn't expose its view; the V/X/q file controls
    -- are diffview-only.
    require("anvil.logger").debug("[FORGE REVIEW] diff viewer returned no view; file controls unavailable")
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
---review tree after GitHub accepts the update. On success, a non-nil `err`
---carries a warning: GitHub was updated but the local tree could not be.
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

    -- The mutation is async: the view may have been closed before GitHub
    -- answered.
    if not view_is_open(view) then
      cb(true, "marked on GitHub, but the diff view is closed")
      return
    end

    if view.anvil_viewed_paths then
      view.anvil_viewed_paths[entry.path] = true
    end

    local removed, position = M.hide_reviewed_file(view, entry, { keep_entry = true })
    if removed then
      view.anvil_hidden_entries = view.anvil_hidden_entries or {}
      table.insert(view.anvil_hidden_entries, { entry = entry, path = entry.path, position = position })
      cb(true, nil)
    else
      cb(true, "marked on GitHub, but the file tree could not be updated")
    end
  end)
end

---Unmarks the most recently viewed file on GitHub and restores it in the
---review tree. On success, a non-nil `err` carries a warning as in
---`mark_current_file_viewed`.
---@param cb fun(success: boolean, err: string|nil)|nil
function M.unmark_last_viewed_file(cb)
  cb = cb or function() end
  if not current_topic then
    cb(false, "no pull request is being reviewed")
    return
  end

  local view = current_diff_view()
  local stack = view and view.anvil_hidden_entries
  local hidden = stack and stack[#stack]
  if not hidden then
    cb(false, "no file was marked viewed in this review")
    return
  end

  forge().unmark_pullreq_file_viewed(current_topic, hidden.path, function(success, err)
    if not success then
      cb(false, err)
      return
    end

    if not view_is_open(view) then
      cb(true, "unmarked on GitHub, but the diff view is closed")
      return
    end

    -- Pop only after the mutation succeeded; the stack may have grown since.
    for i = #stack, 1, -1 do
      if stack[i] == hidden then
        table.remove(stack, i)
        break
      end
    end
    if view.anvil_viewed_paths then
      view.anvil_viewed_paths[hidden.path] = nil
    end

    if M.restore_hidden_file(view, hidden.entry, hidden.position) then
      cb(true, nil)
    else
      cb(true, "unmarked on GitHub, but the file tree could not be updated")
    end
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
