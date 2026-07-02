local actions = require("anvil.popups.dispatch.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilDispatchPopup")
    :group_heading("Dispatch")
    :action("s", "status", actions.status)
    :action("c", "commit", actions.commit)
    :action("d", "diff", actions.diff)
    :action("l", "log", actions.log)
    :action("b", "branch", actions.branch)
    :action("r", "remote", actions.remote)
    :action("z", "stash", actions.stash)
    :action("N", "forge", actions.forge)
    :action("!", "run", actions.run)
    :action("W", "patch", actions.patch)
    :action("O", "submodule", actions.submodule)
    :action("R", "repositories", actions.repos)
    :env(env)
    :build()

  p:show()
  return p
end

return M
