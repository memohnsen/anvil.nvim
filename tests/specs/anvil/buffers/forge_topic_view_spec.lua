local TopicView = require("anvil.buffers.forge_topic_view")
local input = require("anvil.lib.input")
local forge = require("anvil.forge")

describe("Forge topic view", function()
  local original_input
  local original_comment_topic
  local original_edit_topic_title
  local original_edit_topic_labels
  local original_edit_topic_body
  local original_edit_topic_assignees
  local original_edit_topic_milestone
  local original_add_reaction
  local original_add_pullreq_reviewers
  local original_remove_pullreq_reviewers
  local original_reply_review_thread
  local original_resolve_review_thread
  local original_unresolve_review_thread
  local original_add_pending_review_comment
  local original_pending_review_comments
  local original_submit_pullreq_review
  local original_mark_topic_read
  local original_mark_topic_unread
  local original_save_topic_mark
  local original_mark_topic_done
  local original_toggle_topic_state
  local original_pull_topic

  before_each(function()
    original_input = input.get_user_input
    original_comment_topic = forge.comment_topic
    original_edit_topic_title = forge.edit_topic_title
    original_edit_topic_labels = forge.edit_topic_labels
    original_edit_topic_body = forge.edit_topic_body
    original_edit_topic_assignees = forge.edit_topic_assignees
    original_edit_topic_milestone = forge.edit_topic_milestone
    original_add_reaction = forge.add_reaction
    original_add_pullreq_reviewers = forge.add_pullreq_reviewers
    original_remove_pullreq_reviewers = forge.remove_pullreq_reviewers
    original_reply_review_thread = forge.reply_review_thread
    original_resolve_review_thread = forge.resolve_review_thread
    original_unresolve_review_thread = forge.unresolve_review_thread
    original_add_pending_review_comment = forge.add_pending_review_comment
    original_pending_review_comments = forge.pending_review_comments
    original_submit_pullreq_review = forge.submit_pullreq_review
    original_mark_topic_read = forge.mark_topic_read
    original_mark_topic_unread = forge.mark_topic_unread
    original_save_topic_mark = forge.save_topic_mark
    original_mark_topic_done = forge.mark_topic_done
    original_toggle_topic_state = forge.toggle_topic_state
    original_pull_topic = forge.pull_topic
  end)

  after_each(function()
    input.get_user_input = original_input
    forge.comment_topic = original_comment_topic
    forge.edit_topic_title = original_edit_topic_title
    forge.edit_topic_labels = original_edit_topic_labels
    forge.edit_topic_body = original_edit_topic_body
    forge.edit_topic_assignees = original_edit_topic_assignees
    forge.edit_topic_milestone = original_edit_topic_milestone
    forge.add_reaction = original_add_reaction
    forge.add_pullreq_reviewers = original_add_pullreq_reviewers
    forge.remove_pullreq_reviewers = original_remove_pullreq_reviewers
    forge.reply_review_thread = original_reply_review_thread
    forge.resolve_review_thread = original_resolve_review_thread
    forge.unresolve_review_thread = original_unresolve_review_thread
    forge.add_pending_review_comment = original_add_pending_review_comment
    forge.pending_review_comments = original_pending_review_comments
    forge.submit_pullreq_review = original_submit_pullreq_review
    forge.mark_topic_read = original_mark_topic_read
    forge.mark_topic_unread = original_mark_topic_unread
    forge.save_topic_mark = original_save_topic_mark
    forge.mark_topic_done = original_mark_topic_done
    forge.toggle_topic_state = original_toggle_topic_state
    forge.pull_topic = original_pull_topic
  end)

  it("renders stored topic metadata", function()
    forge.pending_review_comments = function()
      return {
        {
          path = "lua/anvil/forge/init.lua",
          line = 99,
          body = "Queued review note.",
        },
      }
    end

    local view = TopicView.new {
      kind = "pullreq",
      number = 42,
      title = "Add a topic buffer",
      state = "OPEN",
      author = "mona",
      updated_at = "2026-07-02T12:00:00Z",
      labels = { { name = "feature" } },
      assignees = { "hubot" },
      reactions = {
        { content = "THUMBS_UP", count = 2 },
        { content = "HEART", count = 1 },
      },
      draft = true,
      head = "topic-buffer",
      base = "main",
      url = "https://github.com/memohnsen/anvil.nvim/pull/42",
      body = "This adds a first-class topic buffer.",
      comments = {
        {
          id = "IC_1",
          author = "octocat",
          created_at = "2026-07-02T13:00:00Z",
          body = "Looks useful.",
          reactions = {
            { content = "ROCKET", count = 3 },
          },
        },
      },
      reviews = {
        {
          author = "hubot",
          state = "APPROVED",
          submitted_at = "2026-07-02T14:00:00Z",
          body = "Ship it.",
        },
      },
      review_threads = {
        {
          id = "PRRT_kwDO",
          path = "lua/anvil/forge/init.lua",
          line = 88,
          resolved = false,
          outdated = true,
          comments = {
            {
              id = "PRRC_1",
              author = "mona",
              created_at = "2026-07-02T15:00:00Z",
              diff_hunk = "@@ -1,2 +1,2 @@\n-old\n+new",
              body = "Can we keep the old behavior here?\n```suggestion\nnew behavior\n```",
              reactions = {
                { content = "EYES", count = 1 },
              },
            },
          },
        },
      },
      review_requests = { "mona", "team-reviewers" },
      detail_synced_at = "2026-07-02T14:00:00Z",
    }

    view:open("split")

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Pull request #42: Add a topic buffer", 1, true) ~= nil)
    assert.True(rendered:find("Author:     mona", 1, true) ~= nil)
    assert.True(rendered:find("Labels:     feature", 1, true) ~= nil)
    assert.True(rendered:find("Reactions:  +1 2, heart 1", 1, true) ~= nil)
    assert.True(rendered:find("Head:       topic-buffer", 1, true) ~= nil)
    assert.True(rendered:find("Reviewers:  mona, team-reviewers", 1, true) ~= nil)
    assert.True(rendered:find("Description:", 1, true) ~= nil)
    assert.True(rendered:find("This adds a first-class topic buffer.", 1, true) ~= nil)
    assert.True(rendered:find("Comment 1: @octocat 2026-07-02T13:00:00Z", 1, true) ~= nil)
    assert.True(rendered:find("Reactions: rocket 3", 1, true) ~= nil)
    assert.True(rendered:find("Looks useful.", 1, true) ~= nil)
    assert.True(rendered:find("@hubot APPROVED 2026-07-02T14:00:00Z", 1, true) ~= nil)
    assert.True(rendered:find("Ship it.", 1, true) ~= nil)
    assert.True(rendered:find("Review Threads:", 1, true) ~= nil)
    assert.True(rendered:find("Thread 1: lua/anvil/forge/init.lua:88 (unresolved, outdated)", 1, true) ~= nil)
    assert.True(rendered:find("Thread comment 1.1: @mona 2026-07-02T15:00:00Z", 1, true) ~= nil)
    assert.True(rendered:find("Reactions: eyes 1", 1, true) ~= nil)
    assert.True(rendered:find("@@ -1,2 +1,2 @@", 1, true) ~= nil)
    assert.True(rendered:find("Can we keep the old behavior here?", 1, true) ~= nil)
    assert.True(rendered:find("Suggestion 1.1.1: lua/anvil/forge/init.lua:88-88", 1, true) ~= nil)
    assert.True(rendered:find("Pending Review Comments:", 1, true) ~= nil)
    assert.True(rendered:find("Pending 1: lua/anvil/forge/init.lua:99", 1, true) ~= nil)
    assert.True(rendered:find("Queued review note.", 1, true) ~= nil)

    view.buffer:close(true)
  end)

  it("comments on the current topic and refreshes details", function()
    local topic = { kind = "issue", number = 7, title = "Needs a comment", state = "OPEN" }
    local commented_topic
    local comment_body
    local refreshed_topic
    local view = TopicView.new(topic)

    forge.comment_topic = function(t, body, cb)
      commented_topic = t
      comment_body = body
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      refreshed_topic = t
      cb(true, nil, vim.tbl_extend("force", t, { body = "fresh body" }))
    end

    view:open("split")
    view:comment()
    view.post_editor.buffer:set_lines(0, -1, false, { "I can reproduce this.", "With more detail." })
    view.post_editor:submit()

    assert.are.same(topic, commented_topic)
    assert.are.same("I can reproduce this.\nWith more detail.", comment_body)
    assert.are.same(topic, refreshed_topic)
    assert.are.same("fresh body", view.topic.body)

    view.buffer:close(true)
  end)

  it("edits title and state on the current topic", function()
    local topic = { kind = "pullreq", number = 9, title = "Old title", state = "OPEN" }
    local edited_topic
    local edited_title
    local toggled_topic
    local view = TopicView.new(topic)

    input.get_user_input = function()
      return "New title"
    end

    forge.edit_topic_title = function(t, title, cb)
      edited_topic = t
      edited_title = title
      cb(true)
    end

    forge.toggle_topic_state = function(t, cb)
      toggled_topic = t
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:edit_title()
    view:toggle_state()

    assert.are.same(topic, edited_topic)
    assert.are.same("New title", edited_title)
    assert.are.same(topic, toggled_topic)
    assert.are.same("CLOSED", view.topic.state)

    view.buffer:close(true)
  end)

  it("adds a reaction on the current topic and refreshes details", function()
    local topic = { kind = "issue", id = "I_kwDO", number = 12, title = "Reactable", state = "OPEN" }
    local reaction
    local refreshed_topic
    local view = TopicView.new(topic)

    input.get_user_input = function()
      return "heart"
    end

    forge.add_reaction = function(t, content, cb)
      reaction = { topic = t, content = content }
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      refreshed_topic = t
      cb(true, nil, vim.tbl_extend("force", t, { reactions = { { content = "HEART", count = 1 } } }))
    end

    view:open("split")
    view:add_reaction()

    assert.are.same(topic, reaction.topic)
    assert.are.same("heart", reaction.content)
    assert.are.same(topic, refreshed_topic)
    assert.are.same("HEART", view.topic.reactions[1].content)

    view.buffer:close(true)
  end)

  it("updates local topic marks from the topic buffer", function()
    local topic = { kind = "issue", number = 18, title = "Mark me", state = "OPEN", unread = true }
    local saved_value
    local view = TopicView.new(topic)

    forge.mark_topic_read = function(t, cb)
      t.unread = false
      cb(true)
    end

    forge.mark_topic_unread = function(t, cb)
      t.unread = true
      cb(true)
    end

    forge.save_topic_mark = function(t, saved, cb)
      saved_value = saved
      t.saved = saved
      cb(true)
    end

    forge.mark_topic_done = function(t, cb)
      t.done = true
      t.unread = false
      cb(true)
    end

    view:open("split")
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Marks:      unread", 1, true) ~= nil)

    view:mark_read()
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Marks:      -", 1, true) ~= nil)

    view:mark_unread()
    view:toggle_saved()
    assert.True(saved_value)
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Marks:      unread, saved", 1, true) ~= nil)

    view:mark_done()
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Marks:      saved, done", 1, true) ~= nil)

    view.buffer:close(true)
  end)

  it("adds reactions to comments and review thread comments by number", function()
    local topic = {
      kind = "pullreq",
      number = 16,
      title = "React to comments",
      state = "OPEN",
      comments = {
        { id = "IC_1", author = "mona", body = "Top-level" },
      },
      review_threads = {
        {
          id = "PRRT_1",
          path = "lua/anvil/init.lua",
          line = 10,
          comments = {
            { id = "PRRC_1", author = "hubot", body = "Inline" },
          },
        },
      },
    }
    local prompts = { "1", "heart", "1", "1", "eyes" }
    local reactions = {}
    local view = TopicView.new(topic)

    input.get_user_input = function()
      return table.remove(prompts, 1)
    end

    forge.add_reaction = function(subject, reaction, cb)
      table.insert(reactions, { subject = subject, reaction = reaction })
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:add_comment_reaction()
    view:add_review_thread_comment_reaction()

    assert.are.same(topic.comments[1], reactions[1].subject)
    assert.are.same("heart", reactions[1].reaction)
    assert.are.same(topic.review_threads[1].comments[1], reactions[2].subject)
    assert.are.same("eyes", reactions[2].reaction)

    view.buffer:close(true)
  end)

  it("edits body, assignees, and milestone on the current topic", function()
    local topic = {
      kind = "issue",
      number = 13,
      title = "Metadata",
      state = "OPEN",
      body = "Old body",
      assignees = { "mona" },
      milestone = "Old milestone",
    }
    local prompts = {
      ["Assignees (comma-separated)"] = "mona,hubot",
      Milestone = "Version 2",
    }
    local edited_body
    local edited_assignees
    local edited_milestone
    local view = TopicView.new(topic)

    input.get_user_input = function(prompt)
      return prompts[prompt]
    end

    forge.edit_topic_body = function(t, body, cb)
      edited_body = { topic = t, body = body }
      cb(true)
    end

    forge.edit_topic_assignees = function(t, assignees, cb)
      edited_assignees = { topic = t, assignees = assignees }
      cb(true)
    end

    forge.edit_topic_milestone = function(t, milestone, cb)
      edited_milestone = { topic = t, milestone = milestone }
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:edit_body()
    view.post_editor.buffer:set_lines(0, -1, false, { "New body", "Second paragraph" })
    view.post_editor:submit()
    view:edit_assignees()
    view:edit_milestone()

    assert.are.same(topic, edited_body.topic)
    assert.are.same("New body\nSecond paragraph", edited_body.body)
    assert.are.same(topic, edited_assignees.topic)
    assert.are.same("mona,hubot", edited_assignees.assignees)
    assert.are.same(topic, edited_milestone.topic)
    assert.are.same("Version 2", edited_milestone.milestone)
    assert.are.same("New body\nSecond paragraph", view.topic.body)
    assert.are.same("Version 2", view.topic.milestone)

    view.buffer:close(true)
  end)

  it("adds and removes pull request reviewers on the current topic", function()
    local topic = {
      kind = "pullreq",
      number = 14,
      title = "Review me",
      state = "OPEN",
      review_requests = { "mona" },
    }
    local prompts = {
      ["Reviewers (comma-separated)"] = "mona,hubot",
      ["Remove reviewers (comma-separated)"] = "mona",
    }
    local added_reviewers
    local removed_reviewers
    local view = TopicView.new(topic)

    input.get_user_input = function(prompt)
      return prompts[prompt]
    end

    forge.add_pullreq_reviewers = function(t, reviewers, cb)
      added_reviewers = { topic = t, reviewers = reviewers }
      cb(true)
    end

    forge.remove_pullreq_reviewers = function(t, reviewers, cb)
      removed_reviewers = { topic = t, reviewers = reviewers }
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:add_reviewers()
    view:remove_reviewers()

    assert.are.same(topic, added_reviewers.topic)
    assert.are.same("mona,hubot", added_reviewers.reviewers)
    assert.are.same(topic, removed_reviewers.topic)
    assert.are.same("mona", removed_reviewers.reviewers)

    view.buffer:close(true)
  end)

  it("replies to, resolves, and unresolves review threads by number", function()
    local topic = {
      kind = "pullreq",
      number = 15,
      title = "Inline thread",
      state = "OPEN",
      review_threads = {
        {
          id = "PRRT_1",
          path = "lua/anvil/init.lua",
          line = 10,
          resolved = false,
          comments = {},
        },
      },
    }
    local reply
    local resolved
    local unresolved
    local view = TopicView.new(topic)

    input.get_user_input = function()
      return "1"
    end

    forge.reply_review_thread = function(thread, body, cb)
      reply = { thread = thread, body = body }
      cb(true)
    end

    forge.resolve_review_thread = function(thread, cb)
      resolved = thread
      cb(true)
    end

    forge.unresolve_review_thread = function(thread, cb)
      unresolved = thread
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:reply_review_thread()
    view.post_editor.buffer:set_lines(0, -1, false, { "Thanks, fixed.", "Added coverage too." })
    view.post_editor:submit()
    view:resolve_review_thread()
    view:unresolve_review_thread()

    assert.are.same(topic.review_threads[1], reply.thread)
    assert.are.same("Thanks, fixed.\nAdded coverage too.", reply.body)
    assert.are.same(topic.review_threads[1], resolved)
    assert.are.same(topic.review_threads[1], unresolved)
    assert.False(view.topic.review_threads[1].resolved)

    view.buffer:close(true)
  end)

  it("queues pending review comments and submits pull request reviews", function()
    local topic = {
      kind = "pullreq",
      id = "PR_kwDO",
      number = 17,
      title = "Review flow",
      state = "OPEN",
    }
    local prompts = { "lua/anvil/forge/init.lua", "23" }
    local pending_comment
    local submitted
    local view = TopicView.new(topic)

    input.get_user_input = function()
      return table.remove(prompts, 1)
    end

    forge.pending_review_comments = function()
      return pending_comment and { pending_comment } or {}
    end

    forge.add_pending_review_comment = function(t, comment)
      pending_comment = vim.tbl_extend("force", comment, { line = tonumber(comment.line), side = "RIGHT" })
      return true
    end

    forge.submit_pullreq_review = function(t, event_name, body, cb)
      submitted = { topic = t, event = event_name, body = body }
      pending_comment = nil
      cb(true)
    end

    forge.pull_topic = function(t, cb)
      cb(true, nil, t)
    end

    view:open("split")
    view:add_pending_review_comment()
    view.post_editor.buffer:set_lines(0, -1, false, { "Please update this line.", "Then this is good." })
    view.post_editor:submit()

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Pending 1: lua/anvil/forge/init.lua:23", 1, true) ~= nil)
    assert.True(rendered:find("Please update this line.", 1, true) ~= nil)

    view:submit_review("APPROVE")
    view.post_editor.buffer:set_lines(0, -1, false, { "Nice work." })
    view.post_editor:submit()

    assert.are.same(topic, submitted.topic)
    assert.are.same("APPROVE", submitted.event)
    assert.are.same("Nice work.", submitted.body)

    view.buffer:close(true)
  end)
end)
