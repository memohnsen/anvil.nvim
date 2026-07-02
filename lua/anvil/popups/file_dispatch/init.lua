local actions = require("anvil.popups.file_dispatch.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilFileDispatchPopup")
    :group_heading("File")
    :action("s", "stage", actions.stage)
    :action("u", "unstage", actions.unstage)
    :action("d", "diff", actions.diff)
    :action("l", "log", actions.log)
    :action("b", "blame", actions.blame)
    :env(env)
    :build()

  p:show()

  return p
end

return M
