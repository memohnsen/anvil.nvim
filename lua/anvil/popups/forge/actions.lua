local M = {}

local forge = require("anvil.forge")
local client = require("anvil.forge.client")
local git = require("anvil.lib.git")
local notification = require("anvil.lib.notification")
local event = require("anvil.lib.event")
local a = require("anvil.lib.async")
local input = require("anvil.lib.input")
local config = require("anvil.config")

local Process = require("anvil.process")

---vim.ui.select, awaitable from the popup's async context.
---@type fun(items: table[], opts: table): table|nil
local select_async = a.wrap(vim.ui.select, 3)

---@return ForgeRepo|nil
local function github_repo()
  local repo = client.get_repo()
  if not repo then
    notification.warn("Forge: no GitHub remote found for this repository")
  end

  return repo
end

---Guard for actions that shell out to gh.
---@return ForgeRepo|nil
local function gh_repo()
  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    return nil
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    return nil
  end

  return github_repo()
end

---@param url string
local function open_url(url)
  if not vim.ui.open then
    notification.warn("Opening URLs requires Neovim >= 0.10")
    return
  end

  notification.info(("Opening %q in your browser."):format(url))
  vim.ui.open(url)
end

---Pick a topic from the local store via vim.ui.select.
---@param kind string "pullreqs"|"issues"
---@param prompt string
---@return table|nil
local function pick_topic(kind, prompt)
  local topics = forge.topics()[kind]
  if not topics or #topics == 0 then
    local label = kind == "pullreqs" and "pull requests" or "issues"
    notification.warn(("Forge: no open %s in local store. Pull forge topics first."):format(label))
    return nil
  end

  return select_async(topics, {
    prompt = prompt,
    format_item = function(item)
      return ("#%d %s"):format(item.number, item.title)
    end,
  })
end

---@return table|nil
local function pick_any_topic(prompt, opts)
  opts = opts or {}
  local topics = forge.topics()
  local items = {}

  for _, issue in ipairs(topics.issues or {}) do
    table.insert(items, issue)
  end

  for _, pullreq in ipairs(topics.pullreqs or {}) do
    table.insert(items, pullreq)
  end

  if opts.include_discussions then
    for _, discussion in ipairs(topics.discussions or {}) do
      table.insert(items, discussion)
    end
  end

  if #items == 0 then
    notification.warn("Forge: no open topics in local store. Pull forge topics first.")
    return nil
  end

  return select_async(items, {
    prompt = prompt,
    format_item = function(item)
      local kind = item.kind == "pullreq" and "pull request" or item.kind == "discussion" and "discussion" or "issue"
      return ("%s #%d %s"):format(kind, item.number, item.title)
    end,
  })
end

---@param cmd string[]
---@return ProcessResult|nil
local function run_gh(cmd)
  local proc = Process.new {
    cmd = cmd,
    cwd = git.repo.worktree_root,
    on_error = function()
      return true
    end,
  }

  return proc:spawn_async()
end

function M.pull(_)
  if not gh_repo() then
    return
  end

  notification.info("Pulling forge topics...")

  forge.pull(function(success, err)
    if success then
      notification.info("Pulling forge topics...done")
    elseif err then
      notification.error("Forge: failed to pull topics: " .. err)
    end
  end)
end

function M.pull_upstream(_)
  if not gh_repo() then
    return
  end

  notification.info("Pulling upstream topics...")
  forge.pull_upstream(function(success, err, upstream)
    if success then
      upstream = upstream or {}
      local n = #(upstream.issues or {}) + #(upstream.pullreqs or {}) + #(upstream.discussions or {})
      -- Upstream topics render in their own status-buffer sections (below the
      -- fork's own), so they never become the fork's base. The status buffer is
      -- refreshed by pull_upstream itself.
      notification.info(("Pulling upstream topics...done (%d topic%s)"):format(n, n == 1 and "" or "s"))
    elseif err then
      notification.error("Forge: failed to pull upstream topics: " .. err)
    end
  end)
end

function M.pull_notifications(_)
  if not gh_repo() then
    return
  end

  notification.info("Pulling forge notifications...")
  forge.pull_notifications(function(success, err)
    if success then
      notification.info("Pulling forge notifications...done")
    elseif err then
      notification.error("Forge: failed to pull notifications: " .. err)
    end
  end)
end

function M.create_issue(_)
  local base = forge.repo_url()
  if not base then
    notification.warn("Forge: no GitHub remote found for this repository")
    return
  end

  open_url(base .. "/issues/new")
end

function M.create_pull_request(_)
  if not gh_repo() then
    return
  end

  run_gh { "gh", "pr", "create", "--web" }
end

function M.create_discussion(_)
  local base = forge.repo_url()
  if not base then
    notification.warn("Forge: no GitHub remote found for this repository")
    return
  end

  open_url(base .. "/discussions/new/choose")
end

function M.comment_topic(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Comment on topic")
  if not topic then
    return
  end

  local body = input.get_user_input("Comment")
  if not body then
    return
  end

  local cli = topic.kind == "pullreq" and "pr" or "issue"
  run_gh { "gh", cli, "comment", tostring(topic.number), "--body", body }
end

function M.browse_issues(_)
  local base = forge.repo_url()
  if base then
    open_url(base .. "/issues")
  else
    notification.warn("Forge: no GitHub remote found for this repository")
  end
end

function M.browse_pullreqs(_)
  local base = forge.repo_url()
  if base then
    open_url(base .. "/pulls")
  else
    notification.warn("Forge: no GitHub remote found for this repository")
  end
end

function M.browse_repo(_)
  local base = forge.repo_url()
  if base then
    open_url(base)
  else
    notification.warn("Forge: no GitHub remote found for this repository")
  end
end

function M.browse_branch(_)
  local base = forge.repo_url()
  if not base then
    notification.warn("Forge: no GitHub remote found for this repository")
    return
  end

  local branch = git.branch.current()
  if not branch then
    notification.warn("Forge: no current branch (detached HEAD?)")
    return
  end

  open_url(("%s/tree/%s"):format(base, branch))
end

function M.browse_topic(_)
  local topic = pick_any_topic("Browse topic", { include_discussions = true })
  if topic then
    forge.browse_topic(topic)
  end
end

function M.list_issues(_)
  if not github_repo() then
    return
  end

  local issue = pick_topic("issues", "Issue")
  if issue then
    forge.browse_topic(issue)
  end
end

function M.list_pullreqs(_)
  if not github_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Pull request")
  if pullreq then
    forge.browse_topic(pullreq)
  end
end

function M.list_topics(_)
  if not github_repo() then
    return
  end

  local topics = forge.topics()
  local items = {}

  for _, issue in ipairs(topics.issues or {}) do
    table.insert(items, { label = "issue", topic = issue })
  end

  for _, pullreq in ipairs(topics.pullreqs or {}) do
    table.insert(items, { label = "pull request", topic = pullreq })
  end

  for _, discussion in ipairs(topics.discussions or {}) do
    table.insert(items, { label = "discussion", topic = discussion })
  end

  if #items == 0 then
    notification.warn("Forge: no open topics in local store. Pull forge topics first.")
    return
  end

  local topic = select_async(items, {
    prompt = "Topic",
    format_item = function(item)
      return ("%s #%d %s"):format(item.label, item.topic.number, item.topic.title)
    end,
  })

  if topic then
    forge.browse_topic(topic.topic)
  end
end

function M.list_issues_buffer(_)
  if not github_repo() then
    return
  end

  require("anvil.buffers.forge_topics_view").new(forge.topics().issues, "Forge Issues"):open()
end

function M.list_pullreqs_buffer(_)
  if not github_repo() then
    return
  end

  require("anvil.buffers.forge_topics_view").new(forge.topics().pullreqs, "Forge Pull Requests"):open()
end

function M.list_discussions_buffer(_)
  if not github_repo() then
    return
  end

  require("anvil.buffers.forge_topics_view").new(forge.topics().discussions, "Forge Discussions"):open()
end

function M.list_notifications(_)
  if not github_repo() then
    return
  end

  require("anvil.buffers.forge_notifications_view").new(forge.topics().notifications):open()
end

function M.checkout_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Checkout pull request")
  if not pullreq then
    return
  end

  local result = run_gh { "gh", "pr", "checkout", tostring(pullreq.number) }
  if result and result:success() then
    notification.info(("Checked out pull request #%d"):format(pullreq.number))
    event.send("ForgePullRequestCheckout", { number = pullreq.number, branch = pullreq.head })
  end
end

function M.checkout_pullreq_worktree(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Checkout pull request in worktree")
  if not pullreq then
    return
  end

  local path = input.get_user_input("Worktree path", { completion = "dir" })
  if not path then
    return
  end

  local branch = pullreq.head or ("pr-" .. pullreq.number)
  local checkout = run_gh { "gh", "pr", "checkout", tostring(pullreq.number), "--branch", branch }
  if checkout and checkout:success() then
    local proc = Process.new {
      cmd = { config.values.git_executable or "git", "worktree", "add", path, branch },
      cwd = git.repo.worktree_root,
      on_error = function()
        return true
      end,
    }
    local result = proc:spawn_async()
    if result and result:success() then
      notification.info(("Checked out pull request #%d in %s"):format(pullreq.number, path))
    end
  end
end

function M.merge_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Merge pull request")
  if not pullreq then
    return
  end

  local method = input.get_choice("Merge method", {
    values = { "&merge", "&squash", "&rebase", "&abort" },
    default = 4,
  })
  if method == "a" then
    return
  end

  local flag = ({ m = "--merge", s = "--squash", r = "--rebase" })[method]
  if flag then
    run_gh { "gh", "pr", "merge", tostring(pullreq.number), flag }
  end
end

function M.approve_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Approve pull request")
  if pullreq then
    local body = input.get_user_input("Approval body")
    run_gh { "gh", "pr", "review", tostring(pullreq.number), "--approve", "--body", body or "" }
  end
end

function M.request_changes_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Request changes")
  if pullreq then
    local body = input.get_user_input("Request changes body")
    run_gh { "gh", "pr", "review", tostring(pullreq.number), "--request-changes", "--body", body or "" }
  end
end

function M.ready_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Mark ready")
  if pullreq then
    run_gh { "gh", "pr", "ready", tostring(pullreq.number) }
  end
end

function M.draft_pullreq(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Mark draft")
  if pullreq then
    run_gh { "gh", "pr", "ready", tostring(pullreq.number), "--undo" }
  end
end

function M.edit_topic_title(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Edit topic title")
  if not topic then
    return
  end

  local title = input.get_user_input("Title", { default = topic.title or "" })
  if not title then
    return
  end

  local cli = topic.kind == "pullreq" and "pr" or "issue"
  run_gh { "gh", cli, "edit", tostring(topic.number), "--title", title }
end

function M.edit_topic_labels(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Edit topic labels")
  if not topic then
    return
  end

  local labels = input.get_user_input("Labels (comma-separated)")
  if not labels then
    return
  end

  local cli = topic.kind == "pullreq" and "pr" or "issue"
  run_gh { "gh", cli, "edit", tostring(topic.number), "--add-label", labels }
end

function M.edit_topic_body(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Edit topic body")
  if not topic then
    return
  end

  local body = input.get_user_input("Body", { default = topic.body or "" })
  if not body then
    return
  end

  forge.edit_topic_body(topic, body)
end

function M.edit_topic_assignees(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Edit topic assignees")
  if not topic then
    return
  end

  local assignees = input.get_user_input("Assignees (comma-separated)")
  if not assignees then
    return
  end

  forge.edit_topic_assignees(topic, assignees)
end

function M.edit_topic_milestone(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Edit topic milestone")
  if not topic then
    return
  end

  local milestone = input.get_user_input("Milestone", { default = topic.milestone or "" })
  if not milestone then
    return
  end

  forge.edit_topic_milestone(topic, milestone)
end

function M.add_topic_reaction(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("React to topic", { include_discussions = true })
  if not topic then
    return
  end

  local reaction = input.get_user_input("Reaction (+1, -1, laugh, confused, heart, hooray, rocket, eyes)", {
    default = "+1",
  })
  if not reaction then
    return
  end

  forge.add_reaction(topic, reaction)
end

function M.add_pullreq_reviewers(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Add reviewers")
  if not pullreq then
    return
  end

  local reviewers = input.get_user_input("Reviewers (comma-separated)")
  if not reviewers then
    return
  end

  forge.add_pullreq_reviewers(pullreq, reviewers)
end

function M.remove_pullreq_reviewers(_)
  if not gh_repo() then
    return
  end

  local pullreq = pick_topic("pullreqs", "Remove reviewers")
  if not pullreq then
    return
  end

  local reviewers = input.get_user_input("Remove reviewers (comma-separated)")
  if not reviewers then
    return
  end

  forge.remove_pullreq_reviewers(pullreq, reviewers)
end

function M.toggle_topic_state(_)
  if not gh_repo() then
    return
  end

  local topic = pick_any_topic("Open/close topic")
  if not topic then
    return
  end

  local cli = topic.kind == "pullreq" and "pr" or "issue"
  local action = topic.state == "OPEN" and "close" or "reopen"
  run_gh { "gh", cli, action, tostring(topic.number) }
end

--- Closes an issue with a specific GitHub state reason. Mirrors magit-forge's
--- `forge-topic-state-set-completed` / `-unplanned`. GitHub state reasons only
--- apply to issues, so pull requests are excluded.
---@param reason string GitHub close reason ("completed" or "not planned")
---@param prompt string
local function close_issue_with_reason(reason, prompt)
  if not gh_repo() then
    return
  end

  local topic = pick_topic("issues", prompt)
  if not topic then
    return
  end

  return run_gh { "gh", "issue", "close", tostring(topic.number), "--reason", reason }
end

function M.close_topic_completed(_)
  close_issue_with_reason("completed", "Close issue as completed")
end

function M.close_topic_unplanned(_)
  close_issue_with_reason("not planned", "Close issue as not planned")
end

--- Marks an issue as a duplicate of another. GitHub's CLI has no native
--- duplicate close reason, so this closes the issue as "not planned" and leaves
--- a "Duplicate of #N" comment, matching how forge records duplicates.
function M.close_topic_duplicate(_)
  if not gh_repo() then
    return
  end

  local topic = pick_topic("issues", "Mark issue as duplicate")
  if not topic then
    return
  end

  local original = input.get_user_input("Duplicate of (issue number or #N)")
  if not original or original == "" then
    return
  end

  local ref = original:gsub("^#", "")
  run_gh { "gh", "issue", "comment", tostring(topic.number), "--body", ("Duplicate of #%s"):format(ref) }
  return run_gh { "gh", "issue", "close", tostring(topic.number), "--reason", "not planned" }
end

function M.mark_topic_read(_)
  local topic = pick_any_topic("Mark topic read", { include_discussions = true })
  if topic then
    forge.mark_topic_read(topic)
  end
end

function M.mark_topic_unread(_)
  local topic = pick_any_topic("Mark topic unread", { include_discussions = true })
  if topic then
    forge.mark_topic_unread(topic)
  end
end

function M.save_topic(_)
  local topic = pick_any_topic("Save topic", { include_discussions = true })
  if topic then
    forge.save_topic_mark(topic, true)
  end
end

function M.unsave_topic(_)
  local topic = pick_any_topic("Unsave topic", { include_discussions = true })
  if topic then
    forge.save_topic_mark(topic, false)
  end
end

function M.mark_topic_done(_)
  local topic = pick_any_topic("Mark topic done", { include_discussions = true })
  if topic then
    forge.mark_topic_done(topic)
  end
end

function M.set_topic_note(_)
  local topic = pick_any_topic("Set note on topic", { include_discussions = true })
  if not topic then
    return
  end

  local note = input.get_user_input("Note (empty to clear)", { default = forge.topic_note(topic) or "" })
  if note == nil then
    return
  end

  forge.set_topic_note(topic, note, function(success, err)
    if success then
      notification.info(note == "" and "Forge: cleared topic note" or "Forge: saved topic note")
    else
      notification.error("Forge: " .. (err or "failed to save topic note"))
    end
  end)
end

-- PR review flow (diffview-backed), PLAN.md §2.6.

function M.start_review(_)
  if not gh_repo() then
    return
  end

  local topic = pick_topic("pullreqs", "Review pull request")
  if topic then
    require("anvil.forge.review").start(topic)
  end
end

function M.review_comment_at_cursor(_)
  local review = require("anvil.forge.review")
  if not review.get_topic() then
    notification.warn("Forge: start a pull request review first (N V s)")
    return
  end

  local body = input.get_user_input("Review comment")
  if not body or body == "" then
    return
  end

  local ok, err = review.comment_at_cursor(body)
  if ok then
    notification.info("Forge: queued pending review comment")
  else
    notification.error("Forge: " .. (err or "failed to queue review comment"))
  end
end

function M.submit_review(_)
  local review = require("anvil.forge.review")
  if not review.get_topic() then
    notification.warn("Forge: start a pull request review first (N V s)")
    return
  end

  local events = { "&1. Comment", "&2. Approve", "&3. Request changes", "&4. Cancel" }
  local choice = input.get_choice("Submit review as", { values = events, default = #events })
  local event_name = ({ ["1"] = "COMMENT", ["2"] = "APPROVE", ["3"] = "REQUEST_CHANGES" })[choice]
  if not event_name then
    return
  end

  local body = input.get_user_input("Review summary (optional)") or ""
  review.submit(event_name, body, function(success, err)
    if success then
      notification.info("Forge: review submitted")
    else
      notification.error("Forge: " .. (err or "failed to submit review"))
    end
  end)
end

return M
