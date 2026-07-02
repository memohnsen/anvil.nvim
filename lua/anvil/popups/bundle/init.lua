local actions = require("anvil.popups.bundle.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilBundlePopup")
    :group_heading("Bundle")
    :action("c", "create", actions.create)
    :action("v", "verify", actions.verify)
    :action("l", "list heads", actions.list_heads)
    :action("u", "unbundle", actions.unbundle)
    :env(env)
    :build()

  p:show()
  return p
end

return M
