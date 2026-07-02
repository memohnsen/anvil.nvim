local actions = require("anvil.popups.shortlog.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilShortlogPopup")
    :group_heading("Shortlog")
    :action("s", "current", actions.current)
    :action("a", "all refs", actions.all)
    :action("r", "range", actions.range)
    :env(env)
    :build()

  p:show()
  return p
end

return M
