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

  it("adds a return-to-Anvil hint to the Diffview file panel help", function()
    assert.are.equal("g? • V: Viewed • X: Unview • q: Anvil", review.file_panel_help_hint("g?"))
    assert.are.equal("g? • V: Viewed • X: Unview • q: Anvil", review.file_panel_help_hint(nil))
  end)

  it("errors when there is no view or file entry", function()
    local target, err = review.target_from_view(nil, 1, 1)
    assert.is_nil(target)
    assert.is_truthy(err)

    target, err = review.target_from_view({}, 1, 1)
    assert.is_nil(target)
    assert.is_truthy(err)
  end)

  it("removes a reviewed file from the Diffview tree and selects the next file", function()
    local first = { path = "first.lua", destroy = function() end }
    local second = { path = "second.lua" }
    local selected
    local view = {
      files = {
        conflicting = {},
        working = { first, second },
        staged = {},
        update_file_trees = function() end,
      },
      panel = {
        ordered_file_list = function()
          return { first, second }
        end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
        reconstrain_cursor = function() end,
        set_cur_file = function(_, file)
          selected = file
        end,
      },
      set_file = function(_, file)
        selected = file
      end,
    }

    assert.is_true(review.hide_reviewed_file(view, first))
    assert.are.same({ second }, view.files.working)
    assert.are.equal(second, selected)
  end)

  it("clears the active entry before removing the last reviewed file", function()
    local detached = false
    local safeguarded = false
    local only = {
      path = "only.lua",
      layout = { detach_files = function() detached = true end },
      destroy = function() end,
    }
    local panel = {
      cur_file = only,
      ordered_file_list = function()
        return { only }
      end,
      set_cur_file = function(self, file)
        self.cur_file = file
      end,
      update_components = function() end,
      render = function() end,
      redraw = function() end,
      reconstrain_cursor = function() end,
    }
    local view = {
      cur_entry = only,
      files = {
        conflicting = {},
        working = { only },
        staged = {},
        update_file_trees = function() end,
      },
      panel = panel,
      file_safeguard = function()
        safeguarded = true
      end,
    }

    assert.is_true(review.hide_reviewed_file(view, only))
    assert.is_nil(view.cur_entry)
    assert.is_nil(panel.cur_file)
    assert.is_true(detached)
    assert.is_true(safeguarded)
  end)

  it("keeps a hidden entry alive and restores it at its old position", function()
    local destroyed = false
    local first = {
      path = "first.lua",
      destroy = function()
        destroyed = true
      end,
    }
    local second = { path = "second.lua" }
    local selected
    local view = {
      files = {
        conflicting = {},
        working = { first, second },
        staged = {},
        update_file_trees = function() end,
      },
      panel = {
        ordered_file_list = function()
          return { first, second }
        end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
        reconstrain_cursor = function() end,
        set_cur_file = function(_, file)
          selected = file
        end,
      },
      set_file = function(_, file)
        selected = file
      end,
    }

    local removed, position = review.hide_reviewed_file(view, first, { keep_entry = true })
    assert.is_true(removed)
    assert.is_false(destroyed)
    assert.are.same({ kind = "working", index = 1 }, position)
    assert.are.same({ second }, view.files.working)

    assert.is_true(review.restore_hidden_file(view, first, position))
    assert.are.same({ first, second }, view.files.working)
    assert.are.equal(first, selected)
  end)

  it("re-hides files marked viewed when the file list is rebuilt", function()
    local bufid = vim.api.nvim_create_buf(false, true)
    local destroyed = {}
    local function make_entry(path)
      return {
        path = path,
        destroy = function()
          table.insert(destroyed, path)
        end,
      }
    end
    local viewed = make_entry("viewed.lua")
    local fresh = make_entry("fresh.lua")
    local safeguarded = false

    local view
    view = {
      anvil_viewed_paths = { ["viewed.lua"] = true },
      files = {
        conflicting = {},
        working = { viewed, fresh },
        staged = {},
        update_file_trees = function() end,
      },
      panel = {
        bufid = bufid,
        ordered_file_list = function()
          return view.files.working
        end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
        reconstrain_cursor = function() end,
        set_cur_file = function() end,
      },
      file_safeguard = function()
        safeguarded = true
      end,
    }
    view.cur_entry = viewed

    review.apply_viewed_paths(view)

    assert.are.same({ fresh }, view.files.working)
    assert.are.same({ "viewed.lua" }, destroyed)
    assert.is_nil(view.cur_entry)
    assert.is_true(safeguarded)

    vim.api.nvim_buf_delete(bufid, { force = true })
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
