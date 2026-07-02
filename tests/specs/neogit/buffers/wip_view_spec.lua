describe("WIP view", function()
  it("renders WIP snapshots", function()
    local view = require("neogit.buffers.wip_view").new({
      {
        kind = "worktree",
        oid = "abc123",
        date = "1 minute ago",
        message = "WIP on main",
      },
    })

    view:open("split")

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Neogit WIP Snapshots", 1, true) ~= nil)
    assert.True(rendered:find("worktree", 1, true) ~= nil)
    assert.True(rendered:find("abc123", 1, true) ~= nil)
    assert.True(rendered:find("WIP on main", 1, true) ~= nil)

    view.buffer:close(true)
  end)
end)
