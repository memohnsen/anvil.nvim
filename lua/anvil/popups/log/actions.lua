local M = {}

local git = require("anvil.lib.git")
local util = require("anvil.lib.util")

local LogViewBuffer = require("anvil.buffers.log_view")
local ReflogViewBuffer = require("anvil.buffers.reflog_view")
local FuzzyFinderBuffer = require("anvil.buffers.fuzzy_finder")

local a = require("anvil.lib.async")

--- Runs `git log` and parses the commits
---@param popup table Contains the argument list
---@param flags table extra CLI flags like --branches or --remotes
---@return CommitLogEntry[]
local function commits(popup, flags)
  return git.log.list(
    util.merge(popup:get_arguments(), flags),
    popup:get_internal_arguments().graph,
    popup.state.env.files,
    false,
    popup:get_internal_arguments().color
  )
end

---@param popup table
---@param flags table
---@return fun(offset: number): CommitLogEntry[]
local function fetch_more_commits(popup, flags)
  return function(offset)
    return commits(popup, util.merge(flags, { ("--skip=%s"):format(offset) }))
  end
end

--- Presents a log view. When the popup was opened from an existing log buffer
--- (via the in-buffer `L` refresh binding), the current buffer is re-rendered
--- in place with the new arguments instead of opening a new split. Mirrors
--- magit's `magit-log-refresh`.
---@param popup table
---@param flags table extra CLI flags for this log mode
---@param header string
local function present(popup, flags, header)
  local commits_list = commits(popup, flags)
  local internal_args = popup:get_internal_arguments()
  local files = popup.state.env.files
  local fetch_func = fetch_more_commits(popup, flags)

  local target = popup.state.env.refresh_target
  if target and target.is_alive and target:is_alive() then
    target:refresh_with(commits_list, internal_args, files, fetch_func, header, git.remote.list())
  else
    LogViewBuffer.new(commits_list, internal_args, files, fetch_func, header, git.remote.list()):open()
  end
end

function M.log_current(popup)
  present(popup, {}, "Commits in " .. (git.branch.current() or ("(detached) " .. git.log.message("HEAD"))))
end

function M.log_related(popup)
  local flags = git.branch.related()
  present(popup, flags, "Commits in " .. table.concat(flags, ", "))
end

function M.log_head(popup)
  present(popup, { "HEAD" }, "Commits in HEAD")
end

function M.log_local_branches(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--branches" }
  present(popup, flags, "Commits in --branches")
end

function M.log_other(popup)
  local options = util.merge(git.refs.list_branches(), git.refs.heads(), git.refs.list_tags())
  local branch = FuzzyFinderBuffer.new(options):open_async()
  if branch then
    present(popup, { branch }, "Commits in " .. branch)
  end
end

function M.log_all_branches(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--branches", "--remotes" }
  present(popup, flags, "Commits in --branches --remotes")
end

function M.log_all_references(popup)
  local flags = { git.branch.is_detached() and "" or "HEAD", "--all" }
  present(popup, flags, "Commits in --all")
end

function M.reflog_current(popup)
  ReflogViewBuffer.new(
    git.reflog.list(git.branch.current(), popup:get_arguments()),
    "Reflog for " .. git.branch.current()
  )
    :open()
end

function M.reflog_head(popup)
  ReflogViewBuffer.new(git.reflog.list("HEAD", popup:get_arguments()), "Reflog for HEAD"):open()
end

function M.reflog_other(popup)
  local branch = FuzzyFinderBuffer.new(git.refs.list_local_branches()):open_async()
  if branch then
    ReflogViewBuffer.new(git.reflog.list(branch, popup:get_arguments()), "Reflog for " .. branch):open()
  end
end

-- NOTE: Prefilling the fuzzy finder with the filepath under the cursor would
-- require the Finder/picker backends (telescope, fzf-lua, snacks, vim.ui.select)
-- to accept an initial query, which they don't currently expose.
---@return function
function M.limit_to_files()
  local fn = function(popup, option)
    if option.value ~= "" then
      popup.state.env.files = nil
      return ""
    end

    local eventignore = vim.o.eventignore
    vim.o.eventignore = "WinLeave"
    local files = FuzzyFinderBuffer.new(git.files.all_tree { with_dir = true }):open_async {
      allow_multi = true,
      refocus_status = false,
    }
    vim.o.eventignore = eventignore

    if not files or vim.tbl_isempty(files) then
      popup.state.env.files = nil
      return ""
    end

    popup.state.env.files = files
    files = util.map(files, function(file)
      return string.format([[ "%s"]], file)
    end)

    return table.concat(files, "")
  end

  return a.wrap(fn, 2)
end

return M
