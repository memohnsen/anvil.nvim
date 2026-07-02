local store = require("neogit.forge.store")

local repo = {
  host = "github.com",
  owner = "neogit-test",
  name = "store-spec",
}

describe("forge store", function()
  it("uses a known local backend", function()
    assert.True(vim.tbl_contains({ "json", "sqlite" }, store.backend()))
  end)

  it("persists and reads topics through the store API", function()
    assert.True(store.save(repo, {
      pullreqs = { { number = 1, title = "PR" } },
      issues = { { number = 2, title = "Issue" } },
      discussions = { { number = 3, title = "Discussion" } },
      synced_at = "2026-07-02T00:00:00Z",
    }))

    local topics = store.get_topics(repo)

    assert.are.same("PR", topics.pullreqs[1].title)
    assert.are.same("Issue", topics.issues[1].title)
    assert.are.same("Discussion", topics.discussions[1].title)
    assert.are.same("2026-07-02T00:00:00Z", topics.synced_at)
  end)

  it("saves notifications without dropping topics", function()
    assert.True(store.save_notifications(repo, {
      { id = "n1", title = "Mention", unread = true },
    }))

    local topics = store.get_topics(repo)

    assert.are.same("PR", topics.pullreqs[1].title)
    assert.are.same("Mention", topics.notifications[1].title)
  end)

  it("updates notification state without dropping topics", function()
    assert.True(store.update_notification(repo, "n1", {
      unread = false,
      saved = true,
      done = true,
    }))

    local topics = store.get_topics(repo)

    assert.are.same("PR", topics.pullreqs[1].title)
    assert.False(topics.notifications[1].unread)
    assert.True(topics.notifications[1].saved)
    assert.True(topics.notifications[1].done)
  end)

  it("updates topic marks without dropping topic details", function()
    assert.True(store.update_topic(repo, { kind = "pullreq", number = 1 }, {
      unread = true,
      saved = true,
      done = false,
    }))

    local topics = store.get_topics(repo)

    assert.are.same("PR", topics.pullreqs[1].title)
    assert.True(topics.pullreqs[1].unread)
    assert.True(topics.pullreqs[1].saved)
    assert.False(topics.pullreqs[1].done)
    assert.is_string(topics.pullreqs[1].mark_updated_at)
  end)

  it("merges topic details into an existing topic", function()
    assert.True(store.save_topic(repo, {
      kind = "pullreq",
      number = 1,
      body = "Detailed body",
      comments = { { id = "IC_1", author = "mona", body = "A comment", reactions = { { content = "HEART", count = 1 } } } },
      reviews = { { author = "hubot", state = "APPROVED" } },
      review_threads = {
        {
          id = "PRRT_1",
          path = "init.lua",
          comments = { { id = "PRRC_1", body = "Inline", reactions = { { content = "EYES", count = 2 } } } },
        },
      },
    }))

    local topics = store.get_topics(repo)

    assert.are.same("PR", topics.pullreqs[1].title)
    assert.are.same("Detailed body", topics.pullreqs[1].body)
    assert.are.same("A comment", topics.pullreqs[1].comments[1].body)
    assert.are.same("IC_1", topics.pullreqs[1].comments[1].id)
    assert.are.same("HEART", topics.pullreqs[1].comments[1].reactions[1].content)
    assert.are.same("APPROVED", topics.pullreqs[1].reviews[1].state)
    assert.are.same("PRRT_1", topics.pullreqs[1].review_threads[1].id)
    assert.are.same("Inline", topics.pullreqs[1].review_threads[1].comments[1].body)
    assert.are.same("PRRC_1", topics.pullreqs[1].review_threads[1].comments[1].id)
    assert.are.same("EYES", topics.pullreqs[1].review_threads[1].comments[1].reactions[1].content)
  end)

  it("stores discussion details separately from issues", function()
    assert.True(store.save_topic(repo, {
      kind = "discussion",
      number = 3,
      title = "A discussion",
      body = "Discussion body",
      comments = { { author = "mona", body = "Discussion comment" } },
    }))

    local topics = store.get_topics(repo)

    assert.are.same("A discussion", topics.discussions[1].title)
    assert.are.same("Discussion comment", topics.discussions[1].comments[1].body)
  end)
end)
