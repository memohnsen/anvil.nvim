---@class AnvilGitLib
---@field repo        AnvilRepo
---@field bisect      AnvilGitBisect
---@field branch      AnvilGitBranch
---@field cherry      AnvilGitCherry
---@field cherry_pick AnvilGitCherryPick
---@field cli         AnvilGitCLI
---@field config      AnvilGitConfig
---@field diff        AnvilGitDiff
---@field fetch       AnvilGitFetch
---@field files       AnvilGitFiles
---@field index       AnvilGitIndex
---@field init        AnvilGitInit
---@field log         AnvilGitLog
---@field merge       AnvilGitMerge
---@field pull        AnvilGitPull
---@field push        AnvilGitPush
---@field rebase      AnvilGitRebase
---@field reflog      AnvilGitReflog
---@field refs        AnvilGitRefs
---@field remote      AnvilGitRemote
---@field reset       AnvilGitReset
---@field rev_parse   AnvilGitRevParse
---@field revert      AnvilGitRevert
---@field sequencer   AnvilGitSequencer
---@field stash       AnvilGitStash
---@field status      AnvilGitStatus
---@field submodule   AnvilGitSubmodule
---@field tag         AnvilGitTag
---@field worktree    AnvilGitWorktree
---@field hooks       AnvilGitHooks
---@field wip         AnvilGitWip
local Git = {}

setmetatable(Git, {
  __index = function(_, k)
    if k == "repo" then
      return require("anvil.lib.git.repository").instance()
    else
      return require("anvil.lib.git." .. k)
    end
  end,
})

return Git
