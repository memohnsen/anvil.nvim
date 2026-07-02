local actions = require("neogit.popups.sparse_checkout.actions")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitSparseCheckoutPopup")
    :switch("c", "cone", "Use cone mode")
    :switch("s", "sparse-index", "Use sparse index")
    :group_heading("Sparse checkout")
    :action("i", "init", actions.init)
    :action("d", "disable", actions.disable)
    :action("s", "set", actions.set)
    :action("a", "add", actions.add)
    :action("r", "reapply", actions.reapply)
    :action("l", "list", actions.list)
    :env(env)
    :build()

  p:show()
  return p
end

return M
