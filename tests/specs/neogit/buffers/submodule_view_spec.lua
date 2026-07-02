describe("Submodule view", function()
  it("renders submodule paths", function()
    local view = require("neogit.buffers.submodule_view").new({
      "vendor/lib-a",
      "vendor/lib-b",
    })

    view:open("split")

    local rendered = table.concat(view.buffer:get_lines(0, -1), "\n")
    assert.True(rendered:find("Neogit Submodules", 1, true) ~= nil)
    assert.True(rendered:find("vendor/lib-a", 1, true) ~= nil)
    assert.True(rendered:find("vendor/lib-b", 1, true) ~= nil)

    view.buffer:close(true)
  end)
end)
