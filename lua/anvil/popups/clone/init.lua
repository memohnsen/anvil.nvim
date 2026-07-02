local actions = require("anvil.popups.clone.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilClonePopup")
    :switch("d", "depth=1", "Create a shallow clone")
    :switch("r", "recurse-submodules", "Initialize submodules after clone")
    :switch("m", "mirror", "Create a mirror clone")
    :switch("b", "bare", "Create a bare clone")
    :group_heading("Clone")
    :action("c", "clone", actions.clone)
    :env(env)
    :build()

  p:show()

  return p
end

return M
