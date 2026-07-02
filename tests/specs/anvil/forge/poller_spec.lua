local poller = require("anvil.forge.poller")
local forge = require("anvil.forge")

describe("forge notification poller", function()
  local original_pull_notifications

  before_each(function()
    original_pull_notifications = forge.pull_notifications
    poller.stop()
  end)

  after_each(function()
    poller.stop()
    forge.pull_notifications = original_pull_notifications
  end)

  it("polls notifications when enabled", function()
    local calls = 0
    forge.pull_notifications = function(cb)
      calls = calls + 1
      cb(false)
    end

    poller.setup({ poll = true, interval = 1 })

    assert.True(vim.wait(100, function()
      return calls > 0
    end))
  end)

  it("does not poll notifications when disabled", function()
    local calls = 0
    forge.pull_notifications = function(cb)
      calls = calls + 1
      cb(false)
    end

    poller.setup({ poll = false, interval = 1 })
    vim.wait(20)

    assert.are.same(0, calls)
  end)
end)
