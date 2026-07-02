local Path = require("anvil.lib.path")

local function read_file(path)
  local lines = {}

  for line in path:iter() do
    table.insert(lines, line)
  end

  return table.concat(lines, "\n")
end

describe("docs", function()
  it("doesn't repeat any tags", function()
    local docs = Path.new(vim.uv.cwd(), "doc", "anvil.txt")
    local tags = {}

    for line in docs:iter() do
      for tag in string.gmatch(line, "%*([%w_]*)%*") do
        assert.Nil(tags[tag])
        tags[tag] = tag
      end
    end
  end)

  it("doesn't reference any undefined tags", function()
    local docs = Path.new(vim.uv.cwd(), "doc", "anvil.txt")
    local tags = {}
    local refs = {}

    for line in docs:iter() do
      for tag in string.gmatch(line, "%*([%w_]*)%*") do
        tags[tag] = true
      end

      for ref in string.gmatch(line, "|([%w_]*)|") do
        table.insert(refs, ref)
      end
    end

    for _, ref in ipairs(refs) do
      if not tags[ref] then
        vim.print("Undefined tag referenced! " .. ref)
      end

      assert.True(tags[ref])
    end
  end)

  describe("README installation docs", function()
    it("documents the supported installation managers", function()
      local readme = read_file(Path.new(vim.uv.cwd(), "README.md"))

      assert.True(readme:find("### `vim.pack`", 1, true) ~= nil)
      assert.True(readme:find("### `lazy.nvim`", 1, true) ~= nil)
      assert.True(readme:find("### `mini.deps`", 1, true) ~= nil)
      assert.True(readme:find("### `packer.nvim`", 1, true) ~= nil)
      assert.True(readme:find("### Vim packages", 1, true) ~= nil)
    end)

    it("keeps vim.pack as the built-in Neovim install example", function()
      local readme = read_file(Path.new(vim.uv.cwd(), "README.md"))

      assert.True(readme:find("Neovim 0.12+ ships a built-in plugin manager, `vim.pack`", 1, true) ~= nil)
      assert.True(readme:find("vim.pack.add", 1, true) ~= nil)
      assert.True(readme:find("https://github.com/memohnsen/anvil.nvim", 1, true) ~= nil)
    end)

    it("documents manual and automatic wip snapshots", function()
      local readme = read_file(Path.new(vim.uv.cwd(), "README.md"))

      assert.True(readme:find("## WIP snapshots", 1, true) ~= nil)
      assert.True(readme:find("! w", 1, true) ~= nil)
      assert.True(readme:find("! W", 1, true) ~= nil)
      assert.True(readme:find("wip = {", 1, true) ~= nil)
      assert.True(readme:find("enabled = true", 1, true) ~= nil)
    end)
  end)
end)
