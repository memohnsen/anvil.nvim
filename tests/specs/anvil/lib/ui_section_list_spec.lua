local Ui = require("anvil.lib.ui")

describe("Ui:section_list", function()
  local function make(item_index)
    return setmetatable({ item_index = item_index }, { __index = Ui })
  end

  it("lists named sections with their starting lines", function()
    local ui = make({
      { name = "untracked", first = 3, last = 5 },
      { name = "unstaged", first = 7, last = 12 },
      { name = "staged", first = 14, last = 20 },
    })

    assert.are.same({
      { name = "untracked", first = 3 },
      { name = "unstaged", first = 7 },
      { name = "staged", first = 14 },
    }, ui:section_list())
  end)

  it("skips entries without a name or start line", function()
    local ui = make({
      { name = "staged", first = 4, last = 6 },
      { first = 8, last = 9 },
      { name = "stashes", last = 12 },
    })

    assert.are.same({ { name = "staged", first = 4 } }, ui:section_list())
  end)

  it("returns an empty list when there are no sections", function()
    assert.are.same({}, make({}):section_list())
    assert.are.same({}, make(nil):section_list())
  end)
end)
