local suggestions = require("neogit.forge.suggestions")

describe("forge suggestions", function()
  it("parses suggestion fences from review comments", function()
    assert.are.same({
      "new line",
      "first\nsecond",
    }, suggestions.parse("Please change this\n```suggestion\nnew line\n```\nAnd this\n```suggestion\nfirst\nsecond\n```"))
  end)

  it("collects suggested changes from review threads", function()
    local topic = {
      review_threads = {
        {
          path = "lua/neogit/init.lua",
          start_line = 4,
          line = 5,
          comments = {
            {
              body = "```suggestion\nreplacement\n```",
            },
          },
        },
      },
    }

    local items = suggestions.collect(topic)

    assert.are.same(1, #items)
    assert.are.same("lua/neogit/init.lua", items[1].path)
    assert.are.same(4, items[1].start_line)
    assert.are.same(5, items[1].end_line)
    assert.are.same("replacement", items[1].body)
  end)

  it("applies suggested changes to the selected file range", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "one", "two", "three", "four" }, vim.fs.joinpath(root, "file.lua"))

    local ok, err = suggestions.apply({
      path = "file.lua",
      start_line = 2,
      end_line = 3,
      body = "dos\ntres",
    }, root)

    assert.True(ok, err)
    assert.are.same({ "one", "dos", "tres", "four" }, vim.fn.readfile(vim.fs.joinpath(root, "file.lua")))
  end)
end)
