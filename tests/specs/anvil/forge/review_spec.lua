local review = require("anvil.forge.review")
local forge = require("anvil.forge")

describe("forge review targeting", function()
  after_each(function()
    review.set_topic(nil)
    forge.clear_pending_review({ id = "PR_1", number = 7 })
  end)

  it("resolves the diff side from the layout window", function()
    local layout = { a = { id = 1001 }, b = { id = 1002 } }

    assert.are.equal("LEFT", review.side_for_window(layout, 1001))
    assert.are.equal("RIGHT", review.side_for_window(layout, 1002))
    assert.is_nil(review.side_for_window(layout, 9999))
    assert.is_nil(review.side_for_window(nil, 1001))
  end)

  it("builds a comment target from the view and cursor", function()
    local view = {
      cur_entry = { path = "lua/foo.lua", oldpath = "lua/old.lua" },
      cur_layout = { a = { id = 1 }, b = { id = 2 } },
    }

    local right = review.target_from_view(view, 2, 42)
    assert.are.same({ path = "lua/foo.lua", line = 42, side = "RIGHT" }, right)

    -- LEFT side prefers the pre-image path (renames).
    local left = review.target_from_view(view, 1, 10)
    assert.are.same({ path = "lua/old.lua", line = 10, side = "LEFT" }, left)
  end)

  it("errors when there is no view or file entry", function()
    local target, err = review.target_from_view(nil, 1, 1)
    assert.is_nil(target)
    assert.is_truthy(err)

    target, err = review.target_from_view({}, 1, 1)
    assert.is_nil(target)
    assert.is_truthy(err)
  end)

  it("queues a pending comment through the review topic", function()
    local topic = { kind = "pullreq", id = "PR_1", number = 7 }
    review.set_topic(topic)
    assert.are.equal(topic, review.get_topic())

    -- Stub the diff view lookup by exercising target_from_view directly, then
    -- confirm the queued comment lands in the forge pending review store.
    local target = review.target_from_view({
      cur_entry = { path = "a.lua" },
      cur_layout = { a = { id = 1 }, b = { id = 2 } },
    }, 2, 5)
    target.body = "looks good"

    local ok = forge.add_pending_review_comment(topic, target)
    assert.is_true(ok)

    local pending = forge.pending_review_comments(topic)
    assert.are.equal(1, #pending)
    assert.are.equal("a.lua", pending[1].path)
    assert.are.equal("RIGHT", pending[1].side)
    assert.are.equal(5, pending[1].line)
  end)

  it("refuses to comment without an active review", function()
    review.set_topic(nil)
    local ok, err = review.comment_at_cursor("body")
    assert.is_false(ok)
    assert.is_truthy(err)
  end)

  it("refuses to start a review on a non-pull-request or ref-less topic", function()
    assert.is_false(review.start({ kind = "issue", number = 1 }))
    assert.is_nil(review.get_topic())

    assert.is_false(review.start({ kind = "pullreq", number = 2, base = "main" }))
    assert.is_nil(review.get_topic())
  end)

  it("submits the queued review and clears the active topic on success", function()
    local topic = { kind = "pullreq", id = "PR_1", number = 7 }
    review.set_topic(topic)

    local captured
    local original_submit = forge.submit_pullreq_review
    forge.submit_pullreq_review = function(t, event_name, body, cb)
      captured = { topic = t, event = event_name, body = body }
      cb(true, nil)
    end

    local result
    review.submit("APPROVE", "ship it", function(success, err)
      result = { success = success, err = err }
    end)

    forge.submit_pullreq_review = original_submit

    assert.are.equal(topic, captured.topic)
    assert.are.equal("APPROVE", captured.event)
    assert.are.equal("ship it", captured.body)
    assert.is_true(result.success)
    -- Active topic is cleared after a successful submit.
    assert.is_nil(review.get_topic())
  end)

  it("keeps the active topic when submit fails", function()
    local topic = { kind = "pullreq", id = "PR_1", number = 7 }
    review.set_topic(topic)

    local original_submit = forge.submit_pullreq_review
    forge.submit_pullreq_review = function(_, _, _, cb)
      cb(false, "network error")
    end

    local result
    review.submit("COMMENT", "", function(success, err)
      result = { success = success, err = err }
    end)

    forge.submit_pullreq_review = original_submit

    assert.is_false(result.success)
    assert.are.equal("network error", result.err)
    assert.are.equal(topic, review.get_topic())
  end)

  it("refuses to submit without an active review", function()
    review.set_topic(nil)
    local result
    review.submit("COMMENT", "", function(success, err)
      result = { success = success, err = err }
    end)
    assert.is_false(result.success)
    assert.is_truthy(result.err)
  end)
end)
