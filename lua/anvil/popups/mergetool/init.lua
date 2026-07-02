local actions = require("anvil.popups.mergetool.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilMergetoolPopup")
    :group_heading("Mergetool")
    :action("m", "run mergetool", actions.mergetool)
    :action("g", "run gui mergetool", actions.gui_mergetool)
    :action("c", "check conflict markers/whitespace", actions.check)
    :env(env)
    :build()

  p:show()
  return p
end

return M
