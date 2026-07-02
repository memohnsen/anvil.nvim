local actions = require("neogit.popups.notes.actions")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitNotesPopup")
    :group_heading("Notes")
    :action("e", "edit", actions.edit)
    :action("a", "add", actions.add)
    :action("A", "append", actions.append)
    :action("s", "show", actions.show)
    :action("r", "remove", actions.remove)
    :new_action_group("Do")
    :action("p", "prune", actions.prune)
    :action("m", "merge", actions.merge)
    :env(env)
    :build()

  p:show()

  return p
end

return M
