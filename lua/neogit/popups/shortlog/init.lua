local actions = require("neogit.popups.shortlog.actions")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitShortlogPopup")
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
