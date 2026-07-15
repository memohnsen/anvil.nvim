describe("Forge list views", function()
  it("renders topic lists", function()
    local view = require("anvil.buffers.forge_topics_view").new({
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
    local view = require("anvil.buffers.forge_topics_view").new({
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
    local view = require("anvil.buffers.forge_notifications_view").new({
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

    -- In the flat style, the header is 4 lines and the first item maps to line 5.
    assert.are.equal("n1", view.line_items[5].id)

    view.buffer:close(true)
  end)

  it("opens a locally synced notification topic in an Anvil buffer", function()
    local forge = require("anvil.forge")
    local topic_view = require("anvil.buffers.forge_topic_view")
    local original_topics = forge.topics
    local original_new = topic_view.new
    local opened
    local topic = { kind = "issue", number = 7, title = "Local issue" }
    local view = require("anvil.buffers.forge_notifications_view").new({
      { id = "n1", repository = "owner/repo", title = "Local issue", url = "https://api.github.com/repos/owner/repo/issues/7" },
    })

    forge.topics = function()
      return { issues = { topic }, pullreqs = {}, discussions = {} }
    end
    topic_view.new = function(selected)
      opened = selected
      return { open = function() end }
    end

    view:open("split")
    view.buffer:move_cursor(5)
    view:open_topic()

    assert.are.same(topic, opened)

    view.buffer:close(true)
    forge.topics = original_topics
    topic_view.new = original_new
  end)

  it("filters notification views", function()
    local view = require("anvil.buffers.forge_notifications_view").new({
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
    local forge = require("anvil.forge")
    local original_pull_notifications = forge.pull_notifications
    local original_topics = forge.topics
    local view = require("anvil.buffers.forge_notifications_view").new({})

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

  it("groups notifications by repository (nested style)", function()
    local view = require("anvil.buffers.forge_notifications_view").new({
      { id = "n1", unread = true, reason = "mention", repository = "owner/alpha", title = "One" },
      { id = "n2", unread = true, reason = "assign", repository = "owner/beta", title = "Two" },
      { id = "n3", unread = true, reason = "review", repository = "owner/alpha", title = "Three" },
    })

    view:open("split")
    view:set_filter("all")
    view:toggle_grouping()

    local lines = view.buffer:get_lines(0, -1)
    local rendered = table.concat(lines, "\n")
    assert.True(rendered:find("Style: grouped", 1, true) ~= nil)

    -- A repository header line appears exactly once per repo, and item rows are
    -- indented beneath it.
    local alpha_header, beta_header
    for i, line in ipairs(lines) do
      if line == "owner/alpha" then
        alpha_header = i
      elseif line == "owner/beta" then
        beta_header = i
      end
    end
    assert.is_truthy(alpha_header)
    assert.is_truthy(beta_header)

    -- The line immediately after the alpha header maps to an alpha notification.
    local first_alpha = view.line_items[alpha_header + 1]
    assert.is_truthy(first_alpha)
    assert.are.equal("owner/alpha", first_alpha.repository)

    view.buffer:close(true)
  end)

  it("sorts topic lists by tablist columns", function()
    local view = require("anvil.buffers.forge_topics_view").new({
      { kind = "issue", number = 1, state = "OPEN", title = "Bravo", updated_at = "2024-01-01T00:00:00Z" },
      { kind = "issue", number = 3, state = "OPEN", title = "Alpha", updated_at = "2024-03-01T00:00:00Z" },
      { kind = "issue", number = 2, state = "CLOSED", title = "Charlie", updated_at = "2024-02-01T00:00:00Z" },
    }, "Forge Topics")

    view:open("split")
    view:set_filter("all")

    local function order()
      local nums = {}
      for _, topic in ipairs(view:sorted_topics()) do
        table.insert(nums, topic.number)
      end
      return nums
    end

    -- Default: number descending.
    assert.are.same({ 3, 2, 1 }, order())
    assert.True(table.concat(view.buffer:get_lines(0, -1), "\n"):find("Sort: number v", 1, true) ~= nil)

    -- Reverse direction -> number ascending.
    view:reverse_sort()
    assert.are.same({ 1, 2, 3 }, order())

    -- Cycle to updated (descending): newest updated_at first.
    view:cycle_sort()
    assert.are.same({ 3, 2, 1 }, order())

    -- Cycle to state (ascending): CLOSED before OPEN.
    view:cycle_sort()
    assert.are.equal(2, order()[1])

    -- Cycle to title (ascending): Alpha, Bravo, Charlie -> #3, #1, #2.
    view:cycle_sort()
    assert.are.same({ 3, 1, 2 }, order())

    view.buffer:close(true)
  end)
end)
