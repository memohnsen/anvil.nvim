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

  it("exposes the numeric prefix argument to actions (C-u analog)", function()
    local instance = popup
      .builder()
      :name("AnvilPrefixArgSpecPopup")
      :switch("v", "verbose", "Verbose")
      :build()

    -- No prefix by default.
    assert.are.equal(0, instance:get_prefix())
    assert.is_false(instance:has_prefix())

    -- Simulate the capture that the action mapping performs.
    instance.state.prefix = 3
    assert.are.equal(3, instance:get_prefix())
    assert.is_true(instance:has_prefix())
  end)

  it("filters argument suffixes by transient display level (C-x l)", function()
    local ui = require("anvil.lib.popup.ui")

    local instance = popup
      .builder()
      :name("AnvilTransientLevelSpecPopup")
      :switch("v", "verbose", "Verbose")
      :switch("z", "advanced", "Advanced", { level = 5 })
      :option("m", "message", "", "Message", { level = 7 })
      :build()

    -- Default level is magit's 4.
    assert.are.equal(4, instance.state.display_level)
    assert.are.equal(1, instance.state.args[1].level)
    assert.are.equal(5, instance.state.args[2].level)
    assert.are.equal(7, instance.state.args[3].level)

    -- At the default level, only the level-1 switch shows.
    assert.is_true(ui.arg_visible(instance.state.args[1], instance.state.display_level))
    assert.is_false(ui.arg_visible(instance.state.args[2], instance.state.display_level))
    assert.is_false(ui.arg_visible(instance.state.args[3], instance.state.display_level))

    -- Cycle 4 -> 7: everything visible.
    instance:cycle_level()
    assert.are.equal(7, instance.state.display_level)
    assert.is_true(ui.arg_visible(instance.state.args[2], instance.state.display_level))
    assert.is_true(ui.arg_visible(instance.state.args[3], instance.state.display_level))

    -- Cycle 7 -> 1: only level-1 visible.
    instance:cycle_level()
    assert.are.equal(1, instance.state.display_level)
    assert.is_true(ui.arg_visible(instance.state.args[1], instance.state.display_level))
    assert.is_false(ui.arg_visible(instance.state.args[2], instance.state.display_level))

    -- Cycle 1 -> 4: back to default.
    instance:cycle_level()
    assert.are.equal(4, instance.state.display_level)
  end)
end)
