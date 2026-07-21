local subject = require("anvil.lib.util")

describe("lib.util", function()
  describe("#memoize", function()
    it("caches results until cleared", function()
      local calls = 0
      local fn = subject.memoize(function()
        calls = calls + 1
        return calls
      end)

      assert.are.same(1, fn())
      assert.are.same(1, fn())
      assert.are.same(1, calls)

      subject.clear_memoized()

      assert.are.same(2, fn())
      assert.are.same(2, calls)
    end)
  end)

  describe("#str_first_char", function()
    it("returns the first ASCII character", function()
      assert.are.same("s", subject.str_first_char("seconds"))
    end)

    it("returns the first UTF-8 character", function()
      assert.are.same("秒", subject.str_first_char("秒前"))
    end)
  end)
end)
