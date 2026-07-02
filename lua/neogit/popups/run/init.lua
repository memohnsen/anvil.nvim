local popup = require("neogit.lib.popup")
local actions = require("neogit.popups.run.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitRunPopup")
    :group_heading("Run")
    :action("!", "Git command (in worktree root)", actions.git_command)
    :action("p", "Git command (in current directory)", actions.git_command_cwd)
    :action("s", "Shell command (in worktree root)", actions.shell_command)
    :action("S", "Shell command (in current directory)", actions.shell_command_cwd)
    :action("w", "Save WIP snapshot", actions.wip_snapshot)
    :action("W", "Save index WIP snapshot", actions.wip_snapshot_index)
    :action("l", "List/apply WIP snapshots", actions.wip_list)
    :env(env)
    :build()

  p:show()

  return p
end

return M
