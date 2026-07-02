local client = require("anvil.forge.client")
local queries = require("anvil.forge.queries")
local store = require("anvil.forge.store")
local notification = require("anvil.lib.notification")
local event = require("anvil.lib.event")
local util = require("anvil.lib.util")
local logger = require("anvil.logger")

---Public API for the forge subsystem. Modeled on magit/forge: topics are
---pulled explicitly from GitHub (via the gh CLI) into a local store, and
---rendered from disk everywhere else.
---@class AnvilForge
local M = {}

-- Safety valve for pagination: 10 pages of 100 topics each.
local MAX_PAGES = 10
local pending_reviews = {}

local REACTION_CONTENT = {
  ["+1"] = "THUMBS_UP",
  thumbs_up = "THUMBS_UP",
  thumbsup = "THUMBS_UP",
  ["-1"] = "THUMBS_DOWN",
  thumbs_down = "THUMBS_DOWN",
  thumbsdown = "THUMBS_DOWN",
  laugh = "LAUGH",
  confused = "CONFUSED",
  heart = "HEART",
  hooray = "HOORAY",
  rocket = "ROCKET",
  eyes = "EYES",
}

local REVIEW_EVENTS = {
  approve = "APPROVE",
  approved = "APPROVE",
  ["request-changes"] = "REQUEST_CHANGES",
  request_changes = "REQUEST_CHANGES",
  changes_requested = "REQUEST_CHANGES",
  comment = "COMMENT",
  commented = "COMMENT",
}

---@param value string
---@return string
local function normalize_review_event(value)
  local event_name = REVIEW_EVENTS[tostring(value or ""):lower()] or tostring(value or ""):upper()
  return event_name:gsub("-", "_")
end

---@param value string
---@return string|nil
local function normalize_reaction_content(value)
  if not value or value == "" then
    return nil
  end

  local key = tostring(value):lower():gsub("%s+", "_"):gsub("-", "_")
  return REACTION_CONTENT[key] or REACTION_CONTENT[value] or tostring(value):upper()
end

---@param node table
---@return table[]
local function normalize_reactions(node)
  return util.map(node.reactionGroups or {}, function(group)
    return {
      content = group.content,
      count = group.users and group.users.totalCount or 0,
    }
  end)
end

---@param node table
---@return table
local function normalize_pullreq(node)
  return {
    kind = "pullreq",
    id = node.id,
    number = node.number,
    title = node.title,
    state = node.state,
    draft = node.isDraft or false,
    author = node.author and node.author.login or nil,
    head = node.headRefName,
    base = node.baseRefName,
    updated_at = node.updatedAt,
    url = node.url,
    labels = util.map((node.labels or {}).nodes or {}, function(label)
      return { name = label.name, color = label.color }
    end),
    assignees = util.map((node.assignees or {}).nodes or {}, function(assignee)
      return assignee.login
    end),
    milestone = node.milestone and node.milestone.title or nil,
    review_requests = util.map((node.reviewRequests or {}).nodes or {}, function(request)
      local reviewer = request.requestedReviewer or {}
      return reviewer.login or reviewer.slug or reviewer.name
    end),
    reactions = normalize_reactions(node),
    review_decision = node.reviewDecision,
  }
end

---@param node table
---@return table
local function normalize_issue(node)
  return {
    kind = "issue",
    id = node.id,
    number = node.number,
    title = node.title,
    state = node.state,
    author = node.author and node.author.login or nil,
    updated_at = node.updatedAt,
    url = node.url,
    labels = util.map((node.labels or {}).nodes or {}, function(label)
      return { name = label.name, color = label.color }
    end),
    assignees = util.map((node.assignees or {}).nodes or {}, function(assignee)
      return assignee.login
    end),
    milestone = node.milestone and node.milestone.title or nil,
    reactions = normalize_reactions(node),
  }
end

local function normalize_discussion(node)
  return {
    kind = "discussion",
    id = node.id,
    number = node.number,
    title = node.title,
    state = "OPEN",
    author = node.author and node.author.login or nil,
    updated_at = node.updatedAt,
    url = node.url,
    category = node.category and node.category.name or nil,
    reactions = normalize_reactions(node),
    body = node.body or "",
    comments = util.map((node.comments or {}).nodes or {}, function(comment)
      return {
        id = comment.id,
        author = comment.author and comment.author.login or nil,
        body = comment.body or "",
        created_at = comment.createdAt,
        updated_at = comment.updatedAt,
        url = comment.url,
        reactions = normalize_reactions(comment),
      }
    end),
  }
end

local function normalize_comment(node)
  return {
    id = node.id,
    author = node.author and node.author.login or nil,
    body = node.body or "",
    created_at = node.createdAt,
    updated_at = node.updatedAt,
    url = node.url,
    reactions = normalize_reactions(node),
  }
end

local function normalize_review(node)
  return {
    author = node.author and node.author.login or nil,
    body = node.body or "",
    state = node.state,
    submitted_at = node.submittedAt,
    url = node.url,
  }
end

local function normalize_review_thread(node)
  return {
    id = node.id,
    path = node.path,
    line = node.line,
    start_line = node.startLine,
    resolved = node.isResolved or false,
    outdated = node.isOutdated or false,
    comments = util.map((node.comments or {}).nodes or {}, function(comment)
      return {
        id = comment.id,
        author = comment.author and comment.author.login or nil,
        body = comment.body or "",
        created_at = comment.createdAt,
        updated_at = comment.updatedAt,
        url = comment.url,
        diff_hunk = comment.diffHunk,
        reactions = normalize_reactions(comment),
      }
    end),
  }
end

local function subject_id(subject, cb)
  if not subject or not subject.id then
    cb(false, "missing forge subject id")
    return nil
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return nil
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return nil
  end

  return subject.id
end

---@param topic table
---@param cb fun(success: boolean, err: string|nil)
---@return string|nil
local function pull_request_id(topic, cb)
  if not topic or topic.kind ~= "pullreq" then
    cb(false, "unsupported topic kind")
    return nil
  end

  if not topic.id then
    cb(false, "missing pull request id")
    return nil
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return nil
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return nil
  end

  return topic.id
end

---@param topic table
---@return string
local function pending_review_key(topic)
  return tostring(topic and (topic.id or topic.number) or "")
end

local function dispatch_status_refresh()
  local ok, refresh_err = pcall(function()
    require("anvil.watcher").instance():dispatch_refresh()
  end)
  if not ok then
    logger.debug("[FORGE] Could not dispatch status refresh: " .. tostring(refresh_err))
  end
end

---@param subject table
---@param reaction string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.add_reaction(subject, reaction, cb)
  cb = cb or function() end

  local id = subject_id(subject, cb)
  if not id then
    return
  end

  local content = normalize_reaction_content(reaction)
  if not content then
    cb(false, "missing reaction")
    return
  end

  client.graphql(queries.add_reaction, { subjectId = id, content = content }, function(_, err)
    cb(err == nil, err)
  end)
end

---@param topic table
---@return table[]
function M.pending_review_comments(topic)
  local key = pending_review_key(topic)
  return vim.deepcopy(pending_reviews[key] or {})
end

---@param topic table
---@param comment {path: string, body: string, line: integer|string, side: string|nil, startLine: integer|string|nil, startSide: string|nil}
---@return boolean
---@return string|nil
function M.add_pending_review_comment(topic, comment)
  if not topic or topic.kind ~= "pullreq" then
    return false, "unsupported topic kind"
  end

  if type(comment) ~= "table" or not comment.path or comment.path == "" or not comment.body or comment.body == "" then
    return false, "invalid review comment"
  end

  local line = tonumber(comment.line)
  if not line then
    return false, "invalid review line"
  end

  local item = {
    path = comment.path,
    body = comment.body,
    line = line,
    side = comment.side or "RIGHT",
  }

  if comment.startLine then
    item.startLine = tonumber(comment.startLine)
    item.startSide = comment.startSide or item.side
  end

  local key = pending_review_key(topic)
  pending_reviews[key] = pending_reviews[key] or {}
  table.insert(pending_reviews[key], item)

  return true, nil
end

---@param topic table
function M.clear_pending_review(topic)
  pending_reviews[pending_review_key(topic)] = nil
end

---@param topic table
---@param event_name string
---@param body string|nil
---@param cb fun(success: boolean, err: string|nil)|nil
function M.submit_pullreq_review(topic, event_name, body, cb)
  cb = cb or function() end

  local id = pull_request_id(topic, cb)
  if not id then
    return
  end

  client.graphql(
    queries.add_pull_request_review,
    {
      pullRequestId = id,
      event = normalize_review_event(event_name),
      body = body or "",
      comments = M.pending_review_comments(topic),
    },
    function(_, err)
      if not err then
        M.clear_pending_review(topic)
      end

      cb(err == nil, err)
    end
  )
end

local function thread_id(thread, cb)
  if not thread or not thread.id then
    cb(false, "missing review thread id")
    return nil
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return nil
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return nil
  end

  return thread.id
end

---@param thread table
---@param body string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.reply_review_thread(thread, body, cb)
  cb = cb or function() end

  local id = thread_id(thread, cb)
  if not id then
    return
  end

  client.graphql(queries.reply_review_thread, { threadId = id, body = body }, function(_, err)
    cb(err == nil, err)
  end)
end

---@param thread table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.resolve_review_thread(thread, cb)
  cb = cb or function() end

  local id = thread_id(thread, cb)
  if not id then
    return
  end

  client.graphql(queries.resolve_review_thread, { threadId = id }, function(_, err)
    cb(err == nil, err)
  end)
end

---@param thread table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.unresolve_review_thread(thread, cb)
  cb = cb or function() end

  local id = thread_id(thread, cb)
  if not id then
    return
  end

  client.graphql(queries.unresolve_review_thread, { threadId = id }, function(_, err)
    cb(err == nil, err)
  end)
end

local function with_detail(topic, node)
  local normalized
  if topic.kind == "pullreq" then
    normalized = normalize_pullreq(node)
  elseif topic.kind == "discussion" then
    normalized = normalize_discussion(node)
  else
    normalized = normalize_issue(node)
  end
  normalized.body = node.body or ""
  normalized.comments = util.map((node.comments or {}).nodes or {}, normalize_comment)
  normalized.detail_synced_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

  if topic.kind == "pullreq" then
    normalized.reviews = util.map((node.reviews or {}).nodes or {}, normalize_review)
    normalized.review_threads = util.map((node.reviewThreads or {}).nodes or {}, normalize_review_thread)
  end

  return normalized
end

---Is the forge usable? Requires gh on $PATH, an authenticated gh session,
---and a GitHub remote on the current repository.
---@return boolean
function M.supported()
  return client.available() and client.authed() and client.get_repo() ~= nil
end

---Follow the pagination cursor for one topic kind, appending normalized
---results, then invoke `done`.
---@param repo ForgeRepo
---@param query string
---@param connection string "pullRequests"|"issues"
---@param normalize fun(node: table): table
---@param acc table[]
---@param cursor string
---@param page number
---@param done fun(err: string|nil)
local function fetch_remaining(repo, query, connection, normalize, acc, cursor, page, done)
  if page > MAX_PAGES then
    done(nil)
    return
  end

  client.graphql(query, { owner = repo.owner, name = repo.name, cursor = cursor }, function(data, err)
    if err or not data then
      done(err or "no data")
      return
    end

    local conn = data.repository and data.repository[connection] or {}
    for _, node in ipairs(conn.nodes or {}) do
      table.insert(acc, normalize(node))
    end

    local page_info = conn.pageInfo or {}
    if page_info.hasNextPage and page_info.endCursor then
      fetch_remaining(repo, query, connection, normalize, acc, page_info.endCursor, page + 1, done)
    else
      done(nil)
    end
  end)
end

---Fetch open pull requests and issues from GitHub, save them to the local
---store, and notify status buffers.
---@param cb fun(success: boolean, err: string|nil)|nil
function M.pull(cb)
  cb = cb or function() end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return
  end

  local repo = client.get_repo()
  if not repo then
    notification.warn("Forge: no GitHub remote found for this repository")
    cb(false, "no GitHub remote")
    return
  end

  client.graphql(queries.topics, { owner = repo.owner, name = repo.name }, function(data, err)
    if err or not data or not data.repository then
      cb(false, err or "no data")
      return
    end

    local pr_conn = data.repository.pullRequests or {}
    local issue_conn = data.repository.issues or {}
    local discussion_conn = data.repository.discussions or {}

    local pullreqs = util.map(pr_conn.nodes or {}, normalize_pullreq)
    local issues = util.map(issue_conn.nodes or {}, normalize_issue)
    local discussions = util.map(discussion_conn.nodes or {}, normalize_discussion)

    local function finish()
      local saved = store.save(repo, {
        pullreqs = pullreqs,
        issues = issues,
        discussions = discussions,
        synced_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      })
      if not saved then
        cb(false, "failed to save forge topics")
        return
      end

      event.send("ForgePulled", {
        repo = repo,
        pullreqs = #pullreqs,
        issues = #issues,
        discussions = #discussions,
      })

      -- Nudge any open status buffers to re-render with the new topics.
      dispatch_status_refresh()

      cb(true, nil)
    end

    local function fetch_discussion_pages()
      local page_info = discussion_conn.pageInfo or {}
      if page_info.hasNextPage and page_info.endCursor then
        fetch_remaining(
          repo,
          queries.discussions,
          "discussions",
          normalize_discussion,
          discussions,
          page_info.endCursor,
          2,
          function(page_err)
            if page_err then
              cb(false, page_err)
              return
            end

            finish()
          end
        )
      else
        finish()
      end
    end

    local function fetch_issue_pages()
      local page_info = issue_conn.pageInfo or {}
      if page_info.hasNextPage and page_info.endCursor then
        fetch_remaining(repo, queries.issues, "issues", normalize_issue, issues, page_info.endCursor, 2, function(page_err)
          if page_err then
            cb(false, page_err)
            return
          end

          fetch_discussion_pages()
        end)
      else
        fetch_discussion_pages()
      end
    end

    local pr_page_info = pr_conn.pageInfo or {}
    if pr_page_info.hasNextPage and pr_page_info.endCursor then
      fetch_remaining(
        repo,
        queries.pullreqs,
        "pullRequests",
        normalize_pullreq,
        pullreqs,
        pr_page_info.endCursor,
        2,
        function(page_err)
          if page_err then
            cb(false, page_err)
            return
          end

          fetch_issue_pages()
        end
      )
    else
      fetch_issue_pages()
    end
  end)
end

---Read topics from the local store. Never touches the network, and never
---errors: returns empty lists when unsupported or unsynced.
---@return ForgeTopics
function M.topics()
  local ok, repo = pcall(client.get_repo)
  if not ok or not repo then
    return { pullreqs = {}, issues = {}, discussions = {}, notifications = {}, synced_at = nil }
  end

  local topics_ok, topics = pcall(store.get_topics, repo)
  if not topics_ok or not topics then
    return { pullreqs = {}, issues = {}, discussions = {}, notifications = {}, synced_at = nil }
  end

  return topics
end

---@param item table
---@return table
local function normalize_notification(item)
  local repo_name = item.repository and item.repository.full_name or nil
  return {
    id = item.id,
    unread = item.unread,
    reason = item.reason,
    updated_at = item.updated_at,
    repository = repo_name,
    title = item.subject and item.subject.title or "",
    type = item.subject and item.subject.type or "",
    url = item.subject and item.subject.url or nil,
    latest_comment_url = item.subject and item.subject.latest_comment_url or nil,
  }
end

---Fetch notifications through gh and persist them in the local store.
---@param cb fun(success: boolean, err: string|nil)|nil
function M.pull_notifications(cb)
  cb = cb or function() end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return
  end

  local repo = client.get_repo()
  if not repo then
    notification.warn("Forge: no GitHub remote found for this repository")
    cb(false, "no GitHub remote")
    return
  end

  client.rest("notifications", {
    fields = { all = "true", participating = "false", per_page = "100" },
    cb = function(data, err)
      if err or type(data) ~= "table" then
        cb(false, err or "no data")
        return
      end

      local notifications = util.map(data, normalize_notification)
      if not store.save_notifications(repo, notifications) then
        cb(false, "failed to save forge notifications")
        return
      end

      cb(true, nil)
    end,
  })
end

---@param id string
---@param attrs table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.update_notification(id, attrs, cb)
  cb = cb or function() end

  local repo = client.get_repo()
  if not repo then
    cb(false, "no GitHub remote")
    return
  end

  if store.update_notification(repo, id, attrs) then
    cb(true, nil)
  else
    cb(false, "failed to save notification")
  end
end

---@param item table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_notification_read(item, cb)
  cb = cb or function() end
  if not item or not item.id then
    cb(false, "invalid notification")
    return
  end

  local function save_local()
    M.update_notification(item.id, { unread = false, done = false }, cb)
  end

  if not client.available() or not client.authed() then
    save_local()
    return
  end

  client.rest("notifications/threads/" .. item.id, {
    method = "PATCH",
    cb = function(_, err)
      if err then
        cb(false, err)
        return
      end

      save_local()
    end,
  })
end

---@param item table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_notification_unread(item, cb)
  cb = cb or function() end
  if not item or not item.id then
    cb(false, "invalid notification")
    return
  end

  M.update_notification(item.id, { unread = true, done = false }, cb)
end

---@param item table
---@param saved boolean
---@param cb fun(success: boolean, err: string|nil)|nil
function M.save_notification(item, saved, cb)
  cb = cb or function() end
  if not item or not item.id then
    cb(false, "invalid notification")
    return
  end

  M.update_notification(item.id, { saved = saved, done = false }, cb)
end

---@param item table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.done_notification(item, cb)
  cb = cb or function() end
  if not item or not item.id then
    cb(false, "invalid notification")
    return
  end

  M.update_notification(item.id, { done = true, unread = false }, cb)
end

---@param topic table
---@param attrs table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.update_topic_mark(topic, attrs, cb)
  cb = cb or function() end
  if not topic or not topic.kind or not topic.number then
    cb(false, "invalid topic")
    return
  end

  local repo = client.get_repo()
  if not repo then
    cb(false, "no GitHub remote")
    return
  end

  if store.update_topic(repo, topic, attrs) then
    dispatch_status_refresh()
    cb(true, nil)
  else
    cb(false, "failed to save topic mark")
  end
end

---@param topic table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_topic_read(topic, cb)
  M.update_topic_mark(topic, { unread = false, done = false }, cb)
end

---@param topic table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_topic_unread(topic, cb)
  M.update_topic_mark(topic, { unread = true, done = false }, cb)
end

---@param topic table
---@param saved boolean
---@param cb fun(success: boolean, err: string|nil)|nil
function M.save_topic_mark(topic, saved, cb)
  M.update_topic_mark(topic, { saved = saved, done = false }, cb)
end

---@param topic table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.mark_topic_done(topic, cb)
  M.update_topic_mark(topic, { done = true, unread = false }, cb)
end

---Fetch one topic's body/comments/reviews and persist it in the local store.
---@param topic table
---@param cb fun(success: boolean, err: string|nil, topic: table|nil)|nil
function M.pull_topic(topic, cb)
  cb = cb or function() end

  if not topic or not topic.kind or not topic.number then
    cb(false, "invalid topic", nil)
    return
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found", nil)
    return
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated", nil)
    return
  end

  local repo = client.get_repo()
  if not repo then
    notification.warn("Forge: no GitHub remote found for this repository")
    cb(false, "no GitHub remote", nil)
    return
  end

  local query = topic.kind == "pullreq" and queries.pullreq_detail
    or topic.kind == "discussion" and queries.discussion_detail
    or queries.issue_detail
  local field = topic.kind == "pullreq" and "pullRequest" or topic.kind == "discussion" and "discussion" or "issue"

  client.graphql(query, { owner = repo.owner, name = repo.name, number = topic.number }, function(data, err)
    local node = data and data.repository and data.repository[field]
    if err or not node then
      cb(false, err or "no data", nil)
      return
    end

    local detailed = vim.tbl_deep_extend("force", topic, with_detail(topic, node))
    if not store.save_topic(repo, detailed) then
      cb(false, "failed to save topic detail", nil)
      return
    end

    cb(true, nil, detailed)
  end)
end

local function topic_cli(topic)
  if topic.kind == "pullreq" then
    return "pr"
  elseif topic.kind == "issue" then
    return "issue"
  end
end

local function command_topic(topic, args, cb)
  cb = cb or function() end

  if not topic or not topic.number then
    cb(false, "missing topic")
    return
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return
  end

  client.command(args, cb)
end

--- Run a GraphQL mutation against a discussion topic, using its node id.
---@param topic table
---@param query string
---@param vars table extra variables merged with { discussionId = topic.id }
---@param cb fun(success: boolean, err: string|nil)|nil
local function discussion_mutation(topic, query, vars, cb)
  cb = cb or function() end

  if not topic or not topic.id then
    cb(false, "missing discussion id")
    return
  end

  if not client.available() then
    notification.warn("Forge: 'gh' executable not found")
    cb(false, "gh not found")
    return
  end

  if not client.authed() then
    notification.warn("Forge: not authenticated with GitHub. Run 'gh auth login'")
    cb(false, "not authenticated")
    return
  end

  vars = vim.tbl_extend("force", { discussionId = topic.id }, vars or {})
  client.graphql(query, vars, function(_, err)
    cb(err == nil, err)
  end)
end

---@param topic table
---@param body string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.comment_topic(topic, body, cb)
  local cli = topic_cli(topic)
  if not cli then
    if topic and topic.kind == "discussion" then
      discussion_mutation(topic, queries.add_discussion_comment, { body = body }, cb)
    elseif cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "comment", tostring(topic.number), "--body", body }, cb)
end

---@param topic table
---@param title string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.edit_topic_title(topic, title, cb)
  local cli = topic_cli(topic)
  if not cli then
    if topic and topic.kind == "discussion" then
      discussion_mutation(topic, queries.update_discussion, { title = title }, cb)
    elseif cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "edit", tostring(topic.number), "--title", title }, cb)
end

---@param topic table
---@param labels string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.edit_topic_labels(topic, labels, cb)
  local cli = topic_cli(topic)
  if not cli then
    notification.warn("Forge: editing discussion labels is not supported")
    if cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "edit", tostring(topic.number), "--add-label", labels }, cb)
end

---@param topic table
---@param body string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.edit_topic_body(topic, body, cb)
  local cli = topic_cli(topic)
  if not cli then
    if topic and topic.kind == "discussion" then
      discussion_mutation(topic, queries.update_discussion, { body = body }, cb)
    elseif cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "edit", tostring(topic.number), "--body", body }, cb)
end

---@param topic table
---@param assignees string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.edit_topic_assignees(topic, assignees, cb)
  local cli = topic_cli(topic)
  if not cli then
    notification.warn("Forge: discussions do not support assignees")
    if cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "edit", tostring(topic.number), "--add-assignee", assignees }, cb)
end

---@param topic table
---@param milestone string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.edit_topic_milestone(topic, milestone, cb)
  local cli = topic_cli(topic)
  if not cli then
    notification.warn("Forge: discussions do not support milestones")
    if cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", cli, "edit", tostring(topic.number), "--milestone", milestone }, cb)
end

---@param topic table
---@param reviewers string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.add_pullreq_reviewers(topic, reviewers, cb)
  if not topic or topic.kind ~= "pullreq" then
    notification.warn("Forge: review requests are only available for pull requests")
    if cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", "pr", "edit", tostring(topic.number), "--add-reviewer", reviewers }, cb)
end

---@param topic table
---@param reviewers string
---@param cb fun(success: boolean, err: string|nil)|nil
function M.remove_pullreq_reviewers(topic, reviewers, cb)
  if not topic or topic.kind ~= "pullreq" then
    notification.warn("Forge: review requests are only available for pull requests")
    if cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  command_topic(topic, { "gh", "pr", "edit", tostring(topic.number), "--remove-reviewer", reviewers }, cb)
end

---@param topic table
---@param cb fun(success: boolean, err: string|nil)|nil
function M.toggle_topic_state(topic, cb)
  local cli = topic_cli(topic)
  if not cli then
    if topic and topic.kind == "discussion" then
      local query = topic.state == "OPEN" and queries.close_discussion or queries.reopen_discussion
      discussion_mutation(topic, query, {}, cb)
    elseif cb then
      cb(false, "unsupported topic kind")
    end
    return
  end

  local action = topic.state == "OPEN" and "close" or "reopen"
  command_topic(topic, { "gh", cli, action, tostring(topic.number) }, cb)
end

---@param url string
---@return boolean
local function open_url(url)
  if not vim.ui.open then
    notification.warn("Opening URLs requires Neovim >= 0.10")
    return false
  end

  notification.info(("Opening %q in your browser."):format(url))
  vim.ui.open(url)

  return true
end

---Base https url for the detected repository.
---@return string|nil
function M.repo_url()
  local repo = client.get_repo()
  if not repo then
    return nil
  end

  return ("https://%s/%s/%s"):format(repo.host, repo.owner, repo.name)
end

---Open a topic in the browser by kind and number.
---@param kind string "pullreq"|"issue"
---@param number number
function M.browse(kind, number)
  local base = M.repo_url()
  if not base then
    notification.warn("Forge: no GitHub remote found for this repository")
    return
  end

  local path = kind == "pullreq" and "pull" or "issues"
  open_url(("%s/%s/%d"):format(base, path, number))
end

---Open a topic (as returned from M.topics()) in the browser.
---@param topic table
function M.browse_topic(topic)
  if topic and topic.url then
    open_url(topic.url)
  elseif topic and topic.kind and topic.number then
    M.browse(topic.kind, topic.number)
  else
    notification.warn("Forge: topic has no url")
  end
end

return M
