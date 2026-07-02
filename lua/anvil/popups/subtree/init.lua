local actions = require("anvil.popups.subtree.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilSubtreePopup")
    :group_heading("Subtree")
    :action("a", "add", actions.add)
    :action("p", "pull", actions.pull)
    :action("P", "push", actions.push)
    :action("s", "split", actions.split)
    :env(env)
    :build()

  p:show()
  return p
end

return M
