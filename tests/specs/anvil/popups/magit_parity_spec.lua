local function action_keys(popup)
  local keys = {}

  for _, group in ipairs(popup.state.actions) do
    for _, action in ipairs(group) do
      if action.keys then
        for _, key in ipairs(action.keys) do
          table.insert(keys, key)
        end
      end
    end
  end

  table.sort(keys)
  return keys
end

describe("Magit parity popups", function()
  it("builds the run/wip popup", function()
    local popup = require("anvil.popups.run").create({})

    assert.are.same({ "!", "S", "W", "l", "p", "s", "w" }, action_keys(popup))

    popup:close()
  end)

  it("builds the patch/am popup", function()
    local popup = require("anvil.popups.patch").create({})

    assert.are.same({ "A", "W", "a", "c", "m", "s", "w" }, action_keys(popup))

    popup:close()
  end)

  it("builds the notes popup", function()
    local popup = require("anvil.popups.notes").create({})

    assert.are.same({ "A", "a", "e", "m", "p", "r", "s" }, action_keys(popup))

    popup:close()
  end)

  it("builds the submodule popup", function()
    local popup = require("anvil.popups.submodule").create({})

    assert.are.same({ "L", "a", "d", "f", "i", "l", "s", "u" }, action_keys(popup))

    popup:close()
  end)

  it("builds the clone popup", function()
    local popup = require("anvil.popups.clone").create({})

    assert.are.same({ "c" }, action_keys(popup))

    popup:close()
  end)

  it("builds the file dispatch popup", function()
    local popup = require("anvil.popups.file_dispatch").create({})

    assert.are.same({ "b", "d", "l", "s", "u" }, action_keys(popup))

    popup:close()
  end)

  it("builds the sparse checkout popup", function()
    local popup = require("anvil.popups.sparse_checkout").create({})

    assert.are.same({ "a", "d", "i", "l", "r", "s" }, action_keys(popup))

    popup:close()
  end)

  it("builds the subtree popup", function()
    local popup = require("anvil.popups.subtree").create({})

    assert.are.same({ "P", "a", "p", "s" }, action_keys(popup))

    popup:close()
  end)

  it("builds the bundle popup", function()
    local popup = require("anvil.popups.bundle").create({})

    assert.are.same({ "c", "l", "u", "v" }, action_keys(popup))

    popup:close()
  end)

  it("builds the shortlog popup", function()
    local popup = require("anvil.popups.shortlog").create({})

    assert.are.same({ "a", "r", "s" }, action_keys(popup))

    popup:close()
  end)

  it("builds the repos popup", function()
    local popup = require("anvil.popups.repos").create({})

    assert.are.same({ "l" }, action_keys(popup))

    popup:close()
  end)

  it("builds the dispatch popup", function()
    local popup = require("anvil.popups.dispatch").create({})

    assert.are.same({ "!", "N", "O", "R", "W", "b", "c", "d", "l", "r", "s", "z" }, action_keys(popup))

    popup:close()
  end)

  it("builds the mergetool popup", function()
    local popup = require("anvil.popups.mergetool").create({})

    assert.are.same({ "c", "g", "m" }, action_keys(popup))

    popup:close()
  end)
end)
