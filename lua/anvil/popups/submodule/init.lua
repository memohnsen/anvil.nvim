local actions = require("anvil.popups.submodule.actions")
local popup = require("anvil.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("AnvilSubmodulePopup")
    :switch("i", "init", "Initialize missing submodules")
    :switch("r", "recursive", "Recurse into nested submodules")
    :switch("R", "remote", "Use submodule remote tracking branch")
    :group_heading("Submodule")
    :action("a", "add", actions.add)
    :action("i", "init", actions.init)
    :action("u", "update", actions.update)
    :action("s", "sync", actions.sync)
    :action("d", "deinit", actions.deinit)
    :new_action_group("Inspect")
    :action("l", "status", actions.status)
    :action("L", "list", actions.list)
    :action("f", "foreach", actions.foreach)
    :env(env)
    :build()

  p:show()

  return p
end

return M
