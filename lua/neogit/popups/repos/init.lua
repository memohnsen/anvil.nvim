local actions = require("neogit.popups.repos.actions")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitReposPopup")
    :group_heading("Repositories")
    :action("l", "list", actions.list)
    :env(env)
    :build()

  p:show()
  return p
end

return M
