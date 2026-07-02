local actions = require("neogit.popups.revert.actions")
local git = require("neogit.lib.git")
local popup = require("neogit.lib.popup")

local M = {}

function M.create(env)
  local in_progress = git.sequencer.pick_or_revert_in_progress()
  -- NOTE: The "edit" switch defaults to enabled; if the user has toggled the
  -- incompatible "no-edit" switch, the persisted state can show both as enabled
  -- on the next open until one is toggled again.

  local p = popup
    .builder()
    :name("NeogitRevertPopup")
    :option_if(not in_progress, "m", "mainline", "", "Replay merge relative to parent")
    :switch_if(
      not in_progress,
      "e",
      "edit",
      "Edit commit messages",
      { enabled = true, incompatible = { "no-edit" } }
    )
    :switch_if(not in_progress, "E", "no-edit", "Don't edit commit messages", { incompatible = { "edit" } })
    :switch_if(not in_progress, "s", "signoff", "Add Signed-off-by lines")
    :option_if(not in_progress, "s", "strategy", "", "Strategy", {
      key_prefix = "=",
      choices = { "octopus", "ours", "resolve", "subtree", "recursive" },
    })
    :option_if(not in_progress, "S", "gpg-sign", "", "Sign using gpg", {
      key_prefix = "-",
    })
    :group_heading("Revert")
    :action_if(not in_progress, "v", "Commit(s)", actions.commits)
    :action_if(not in_progress, "V", "Changes", actions.changes)
    :action_if(((not in_progress) and env.hunk ~= nil), "h", "Hunk", actions.hunk)
    :action_if(in_progress, "v", "continue", actions.continue)
    :action_if(in_progress, "s", "skip", actions.skip)
    :action_if(in_progress, "a", "abort", actions.abort)
    :env(env)
    :build()

  p:show()

  return p
end

return M
