local actions = require("neogit.popups.patch.actions")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeogitPatchPopup")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("3", "3way", "Attempt three-way merge")
    :switch("i", "ignore-space-change", "Ignore whitespace changes")
    :group_heading("Format")
    :action("w", "format patch", actions.format_patch)
    :action("W", "format patch to directory", actions.format_patch_to_directory)
    :new_action_group("Apply")
    :action("a", "apply patch", actions.apply)
    :action("m", "apply mailbox", actions.am)
    :new_action_group("Am")
    :action("c", "continue", actions.am_continue)
    :action("s", "skip", actions.am_skip)
    :action("A", "abort", actions.am_abort)
    :env(env)
    :build()

  p:show()

  return p
end

return M
