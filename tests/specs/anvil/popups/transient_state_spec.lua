local popup = require("anvil.lib.popup")
local config = require("anvil.config")
local state = require("anvil.lib.state")

describe("popup transient state", function()
  before_each(function()
    state.setup(config.values)
    state._reset()
  end)

  it("saves, restores, records, and resets popup argument state", function()
    local invoked = 0
    local instance = popup
      .builder()
      :name("AnvilTransientStateSpecPopup")
      :switch("v", "verbose", "Verbose")
      :option("m", "message", "", "Message")
      :action("x", "run", function()
        invoked = invoked + 1
      end)
      :build()

    local verbose = instance.state.args[1]
    local message = instance.state.args[2]

    instance:toggle_switch(verbose)
    instance:set_option(message, "first")
    instance:save_defaults()

    assert.True(state.get({ "AnvilTransientStateSpecPopup", "verbose" }, false))
    assert.are.same("first", state.get({ "AnvilTransientStateSpecPopup", "message" }, ""))

    instance:record_history()
    message.value = "second"
    instance:record_history()

    assert.are.same("second", message.value)
    instance:restore_previous_history()
    assert.are.same("first", message.value)

    instance:reset_defaults()
    assert.False(verbose.enabled)
    assert.are.same("", message.value)
    assert.is_nil(state.get({ "AnvilTransientStateSpecPopup", "verbose" }, nil))
    assert.is_nil(state.get({ "AnvilTransientStateSpecPopup", "message" }, nil))

    local action = instance.state.actions[1][1]
    action.callback(instance)
    assert.are.same(1, invoked)
  end)
end)
