describe("Forge list views", function()
  it("renders topic lists", function()
    local view = require("neogit.buffers.forge_topics_view").new({
      { kind = "issue", number = 1, state = "OPEN", title = "First issue", unread = true },
      { kind = "pullreq", number = 2, state = "OPEN", title = "First PR", saved = true },
      { kind = "discussion", number = 3, state = "OPEN", title = "First discussion", done = true },
    }, "Forge Topics")

    view:open("split")
    view:set_filter("all")

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Filter: all", 1, true) ~= nil)
    assert.True(rendered:find("Issue #1", 1, true) ~= nil)
    assert.True(rendered:find("PR    #2", 1, true) ~= nil)
    assert.True(rendered:find("Disc  #3", 1, true) ~= nil)
    assert.True(rendered:find("U   Issue #1", 1, true) ~= nil)
    assert.True(rendered:find(" S  PR    #2", 1, true) ~= nil)
    assert.True(rendered:find("  D Disc  #3", 1, true) ~= nil)

    view.buffer:close(true)
  end)

  it("filters topic lists by marks, state, and metadata", function()
    local view = require("neogit.buffers.forge_topics_view").new({
      {
        kind = "issue",
        number = 1,
        state = "OPEN",
        title = "Unread issue",
        unread = true,
        author = "mona",
        labels = { { name = "bug" } },
        assignees = { "hubot" },
        milestone = "v1",
      },
      {
        kind = "pullreq",
        number = 2,
        state = "CLOSED",
        title = "Saved PR",
        saved = true,
        author = "octocat",
        labels = { { name = "feature" } },
        assignees = { "mona" },
        milestone = "v2",
      },
      {
        kind = "discussion",
        number = 3,
        state = "OPEN",
        title = "Done discussion",
        done = true,
        author = "hubot",
      },
    }, "Forge Topics")

    view:open("split")
    view:set_filter("unread")
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Unread issue", 1, true) ~= nil)
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Saved PR", 1, true) == nil)

    view:set_filter("saved")
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Saved PR", 1, true) ~= nil)

    view:set_filter("done")
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Done discussion", 1, true) ~= nil)

    view:set_filter("closed")
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Saved PR", 1, true) ~= nil)
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Unread issue", 1, true) == nil)

    view:set_filter("author", { kind = "author", value = "mona" })
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Unread issue", 1, true) ~= nil)

    view:set_filter("label", { kind = "label", value = "feature" })
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Saved PR", 1, true) ~= nil)

    view:set_filter("assignee", { kind = "assignee", value = "hubot" })
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Unread issue", 1, true) ~= nil)

    view:set_filter("milestone", { kind = "milestone", value = "v2" })
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Saved PR", 1, true) ~= nil)

    view.buffer:close(true)
  end)

  it("renders notifications", function()
    local view = require("neogit.buffers.forge_notifications_view").new({
      { id = "n1", unread = true, saved = true, reason = "mention", repository = "owner/repo", title = "Ping" },
      { id = "n2", done = true, reason = "assign", repository = "owner/repo", title = "Done" },
    })

    view:open("split")

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Forge Notifications", 1, true) ~= nil)
    assert.True(rendered:find("Filter: active", 1, true) ~= nil)
    assert.True(rendered:find("*S  mention", 1, true) ~= nil)
    assert.True(rendered:find("owner/repo", 1, true) ~= nil)
    assert.True(rendered:find("Ping", 1, true) ~= nil)
    assert.True(rendered:find("Done", 1, true) == nil)

    view.buffer:close(true)
  end)

  it("filters notification views", function()
    local view = require("neogit.buffers.forge_notifications_view").new({
      { id = "n1", unread = true, reason = "mention", repository = "owner/repo", title = "Unread" },
      { id = "n2", saved = true, reason = "assign", repository = "owner/repo", title = "Saved" },
      { id = "n3", done = true, reason = "review", repository = "owner/repo", title = "Done" },
    })

    view:open("split")
    view:set_filter("unread")

    local unread = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(unread:find("Filter: unread", 1, true) ~= nil)
    assert.True(unread:find("Unread", 1, true) ~= nil)
    assert.True(unread:find("Saved", 1, true) == nil)
    assert.True(unread:find("Done", 1, true) == nil)

    view:set_filter("saved")
    local saved = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(saved:find("Saved", 1, true) ~= nil)
    assert.True(saved:find("Unread", 1, true) == nil)

    view:set_filter("done")
    local done = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(done:find("Done", 1, true) ~= nil)
    assert.True(done:find("Unread", 1, true) == nil)

    view:set_filter("all")
    local all = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(all:find("Unread", 1, true) ~= nil)
    assert.True(all:find("Saved", 1, true) ~= nil)
    assert.True(all:find("Done", 1, true) ~= nil)

    view.buffer:close(true)
  end)

  it("refreshes notifications from forge", function()
    local forge = require("neogit.forge")
    local original_pull_notifications = forge.pull_notifications
    local original_topics = forge.topics
    local view = require("neogit.buffers.forge_notifications_view").new({})

    forge.pull_notifications = function(cb)
      cb(true)
    end

    forge.topics = function()
      return {
        notifications = {
          { id = "n1", unread = true, reason = "mention", repository = "owner/repo", title = "Fresh" },
        },
      }
    end

    view:open("split")
    view:refresh()

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Fresh", 1, true) ~= nil)

    view.buffer:close(true)
    forge.pull_notifications = original_pull_notifications
    forge.topics = original_topics
  end)
end)
