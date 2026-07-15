local forge = require("anvil.forge")
local client = require("anvil.forge.client")
local store = require("anvil.forge.store")

describe("forge topic actions", function()
  local original_available
  local original_authed
  local original_command
  local original_graphql
  local original_get_repo

  before_each(function()
    original_available = client.available
    original_authed = client.authed
    original_command = client.command
    original_graphql = client.graphql
    original_get_repo = client.get_repo

    client.available = function()
      return true
    end

    client.authed = function()
      return true
    end
  end)

  after_each(function()
    client.available = original_available
    client.authed = original_authed
    client.command = original_command
    client.graphql = original_graphql
    client.get_repo = original_get_repo
    forge.clear_pending_review({ id = "PR_kwDO", number = 42 })
  end)

  it("comments on issues and pull requests with gh", function()
    local calls = {}
    client.command = function(args, cb)
      table.insert(calls, args)
      cb(true)
    end

    forge.comment_topic({ kind = "issue", number = 11 }, "issue body", function(success)
      assert.True(success)
    end)
    forge.comment_topic({ kind = "pullreq", number = 12 }, "pr body", function(success)
      assert.True(success)
    end)

    assert.are.same({ "gh", "issue", "comment", "11", "--body", "issue body" }, calls[1])
    assert.are.same({ "gh", "pr", "comment", "12", "--body", "pr body" }, calls[2])
  end)

  it("creates issues with gh", function()
    local call
    client.command = function(args, cb)
      call = args
      cb(true)
    end

    forge.create_issue("A clear title", "Issue body", function(success)
      assert.True(success)
    end)

    assert.are.same({ "gh", "issue", "create", "--title", "A clear title", "--body", "Issue body" }, call)
  end)

  it("creates pull requests with gh without opening a browser", function()
    local call
    client.command = function(args, cb)
      call = args
      cb(true)
    end

    forge.create_pullreq("A clear title", "Pull request body", function(success)
      assert.True(success)
    end)

    assert.are.same({ "gh", "pr", "create", "--title", "A clear title", "--body", "Pull request body" }, call)
  end)

  it("loads discussion categories and creates a discussion with GraphQL", function()
    local calls = {}
    client.graphql = function(query, variables, cb)
      table.insert(calls, { query = query, variables = variables })
      if query == require("anvil.forge.queries").discussion_categories then
        cb({ repository = { id = "R_123", discussionCategories = { nodes = { { id = "DC_123", name = "Ideas" } } } } })
      else
        cb({}, nil)
      end
    end
    client.get_repo = function()
      return { owner = "owner", name = "repo" }
    end

    forge.discussion_categories(function(categories)
      assert.are.same("R_123", categories[1].repository_id)
      forge.create_discussion(categories[1], "A clear title", "Discussion body")
    end)

    assert.are.same({ owner = "owner", name = "repo" }, calls[1].variables)
    assert.are.same({ repositoryId = "R_123", categoryId = "DC_123", title = "A clear title", body = "Discussion body" }, calls[2].variables)
  end)

  it("edits topic title, labels, body, assignees, milestone, and state with gh", function()
    local calls = {}
    client.command = function(args, cb)
      table.insert(calls, args)
      cb(true)
    end

    forge.edit_topic_title({ kind = "issue", number = 3 }, "A clearer title")
    forge.edit_topic_labels({ kind = "pullreq", number = 4 }, "bug,help wanted")
    forge.edit_topic_body({ kind = "issue", number = 5 }, "Updated body")
    forge.edit_topic_assignees({ kind = "pullreq", number = 6 }, "@me,hubot")
    forge.edit_topic_milestone({ kind = "issue", number = 7 }, "Version 1")
    forge.add_pullreq_reviewers({ kind = "pullreq", number = 8 }, "mona,hubot")
    forge.remove_pullreq_reviewers({ kind = "pullreq", number = 9 }, "hubot")
    forge.toggle_topic_state({ kind = "issue", number = 5, state = "OPEN" })
    forge.toggle_topic_state({ kind = "pullreq", number = 6, state = "CLOSED" })

    assert.are.same({ "gh", "issue", "edit", "3", "--title", "A clearer title" }, calls[1])
    assert.are.same({ "gh", "pr", "edit", "4", "--add-label", "bug,help wanted" }, calls[2])
    assert.are.same({ "gh", "issue", "edit", "5", "--body", "Updated body" }, calls[3])
    assert.are.same({ "gh", "pr", "edit", "6", "--add-assignee", "@me,hubot" }, calls[4])
    assert.are.same({ "gh", "issue", "edit", "7", "--milestone", "Version 1" }, calls[5])
    assert.are.same({ "gh", "pr", "edit", "8", "--add-reviewer", "mona,hubot" }, calls[6])
    assert.are.same({ "gh", "pr", "edit", "9", "--remove-reviewer", "hubot" }, calls[7])
    assert.are.same({ "gh", "issue", "close", "5" }, calls[8])
    assert.are.same({ "gh", "pr", "reopen", "6" }, calls[9])
  end)

  it("replies to and resolves review threads with GraphQL", function()
    local calls = {}
    client.graphql = function(query, variables, cb)
      table.insert(calls, { query = query, variables = variables })
      cb({}, nil)
    end

    forge.reply_review_thread({ id = "PRRT_kwDO" }, "Inline reply", function(success)
      assert.True(success)
    end)
    forge.resolve_review_thread({ id = "PRRT_kwDO" }, function(success)
      assert.True(success)
    end)
    forge.unresolve_review_thread({ id = "PRRT_kwDO" }, function(success)
      assert.True(success)
    end)

    assert.True(calls[1].query:find("addPullRequestReviewThreadReply", 1, true) ~= nil)
    assert.are.same({ threadId = "PRRT_kwDO", body = "Inline reply" }, calls[1].variables)
    assert.True(calls[2].query:find("resolveReviewThread", 1, true) ~= nil)
    assert.are.same({ threadId = "PRRT_kwDO" }, calls[2].variables)
    assert.True(calls[3].query:find("unresolveReviewThread", 1, true) ~= nil)
    assert.are.same({ threadId = "PRRT_kwDO" }, calls[3].variables)
  end)

  it("adds reactions with GraphQL", function()
    local call
    client.graphql = function(query, variables, cb)
      call = { query = query, variables = variables }
      cb({}, nil)
    end

    forge.add_reaction({ id = "I_kwDO" }, "+1", function(success)
      assert.True(success)
    end)

    assert.True(call.query:find("addReaction", 1, true) ~= nil)
    assert.are.same({ subjectId = "I_kwDO", content = "THUMBS_UP" }, call.variables)
  end)

  it("queues pending review comments and submits pull request reviews with GraphQL", function()
    local calls = {}
    client.graphql = function(query, variables, cb)
      table.insert(calls, { query = query, variables = variables })
      cb({}, nil)
    end

    local topic = { kind = "pullreq", id = "PR_kwDO", number = 42 }
    local ok, err = forge.add_pending_review_comment(topic, {
      path = "lua/anvil/forge/init.lua",
      line = "17",
      body = "Please keep this behavior.",
    })

    assert.True(ok)
    assert.is_nil(err)
    assert.are.same({
      {
        path = "lua/anvil/forge/init.lua",
        line = 17,
        side = "RIGHT",
        body = "Please keep this behavior.",
      },
    }, forge.pending_review_comments(topic))

    forge.submit_pullreq_review(topic, "approve", "Looks good overall.", function(success)
      assert.True(success)
    end)

    assert.True(calls[1].query:find("addPullRequestReview", 1, true) ~= nil)
    assert.are.same("PR_kwDO", calls[1].variables.pullRequestId)
    assert.are.same("APPROVE", calls[1].variables.event)
    assert.are.same("Looks good overall.", calls[1].variables.body)
    assert.are.same({
      {
        path = "lua/anvil/forge/init.lua",
        line = 17,
        side = "RIGHT",
        body = "Please keep this behavior.",
      },
    }, calls[1].variables.comments)
    assert.are.same({}, forge.pending_review_comments(topic))
  end)

  it("updates local topic marks through the forge API", function()
    local repo = { host = "github.com", owner = "anvil-test", name = "topic-mark-actions" }
    client.get_repo = function()
      return repo
    end

    assert.True(store.save(repo, {
      issues = {
        { kind = "issue", number = 31, title = "Marked locally", unread = true },
      },
    }))

    local topic = { kind = "issue", number = 31, title = "Marked locally", unread = true }

    forge.mark_topic_read(topic, function(success)
      assert.True(success)
    end)
    forge.save_topic_mark(topic, true, function(success)
      assert.True(success)
    end)
    forge.mark_topic_done(topic, function(success)
      assert.True(success)
    end)

    local stored = store.get_topics(repo).issues[1]
    assert.False(stored.unread)
    assert.True(stored.saved)
    assert.True(stored.done)
  end)

  it("stores and clears a local topic note", function()
    local repo = { host = "github.com", owner = "anvil-test", name = "topic-note-actions" }
    client.get_repo = function()
      return repo
    end

    assert.True(store.save(repo, {
      issues = {
        { kind = "issue", number = 44, title = "Noted" },
      },
    }))

    local topic = { kind = "issue", number = 44, title = "Noted" }

    forge.set_topic_note(topic, "follow up next week", function(success)
      assert.True(success)
    end)
    assert.are.equal("follow up next week", store.get_topics(repo).issues[1].note)
    assert.are.equal("follow up next week", forge.topic_note(store.get_topics(repo).issues[1]))

    -- Clearing empties the note, and topic_note reports it as absent.
    local cleared = store.get_topics(repo).issues[1]
    forge.set_topic_note(cleared, "", function(success)
      assert.True(success)
    end)
    assert.are.equal("", store.get_topics(repo).issues[1].note)
    assert.is_nil(forge.topic_note(store.get_topics(repo).issues[1]))
  end)
end)
