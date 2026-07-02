local popup = require("anvil.lib.popup")
local actions = require("anvil.popups.help.actions")

local M = {}

function M.create(env)
  local p = popup.builder():name("AnvilHelpPopup"):group_heading("Commands")

  -- Split the (long) Commands list across two columns.
  local popups = actions.popups(env)
  for i, cmd in ipairs(popups) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)

    if i == math.ceil(#popups / 2) then
      p = p:new_action_group()
    end
  end

  -- Third column stacks the two smaller groups vertically ("Applying changes"
  -- above "Essential commands") so the popup doesn't run off the right edge.
  p = p:new_action_group("Applying changes")
  for _, cmd in ipairs(actions.actions()) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:group_heading(""):group_heading("Essential commands")
  for _, cmd in ipairs(actions.essential()) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:build()
  p:show()

  return p
end

return M
