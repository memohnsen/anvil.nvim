local ui = require("anvil.buffers.blame_view.ui")

-- Collects all text values in a component subtree, in order.
local function flatten_text(component, acc)
  acc = acc or {}
  if type(component.value) == "string" then
    table.insert(acc, component.value)
  end
  for _, child in ipairs(component.children or {}) do
    flatten_text(child, acc)
  end
  return acc
end

-- Text of the heading row (first child) of the first hunk column.
local function heading_text(view)
  return table.concat(flatten_text(view[1].children[1]), "")
end

describe("blame view ui", function()
  local hunk = {
    oid = "abc123def456",
    abbrev = "abc123d",
    author = "Ada Lovelace",
    author_time = os.time() - 60 * 60 * 24 * 3,
    summary = "Add the analytical engine",
    uncommitted = false,
    lines = { "line one", "line two" },
  }

  it("exposes the magit-style heading styles", function()
    assert.are.same({ "full", "compact", "author" }, ui.STYLES)
  end)

  it("renders the full heading with sha, author, date, and summary", function()
    local text = heading_text(ui.View({ hunk }, "full"))
    assert.is_truthy(text:find("abc123d", 1, true))
    assert.is_truthy(text:find("Ada Lovelace", 1, true))
    assert.is_truthy(text:find("3 days ago", 1, true))
    assert.is_truthy(text:find("Add the analytical engine", 1, true))
  end)

  it("renders the compact heading with sha and date only", function()
    local text = heading_text(ui.View({ hunk }, "compact"))
    assert.is_truthy(text:find("abc123d", 1, true))
    assert.is_truthy(text:find("3 days ago", 1, true))
    assert.is_nil(text:find("Ada Lovelace", 1, true))
    assert.is_nil(text:find("Add the analytical engine", 1, true))
  end)

  it("renders the author heading with sha and author only", function()
    local text = heading_text(ui.View({ hunk }, "author"))
    assert.is_truthy(text:find("abc123d", 1, true))
    assert.is_truthy(text:find("Ada Lovelace", 1, true))
    assert.is_nil(text:find("3 days ago", 1, true))
  end)

  it("defaults to the full style", function()
    assert.are.equal(heading_text(ui.View({ hunk })), heading_text(ui.View({ hunk }, "full")))
  end)
end)
