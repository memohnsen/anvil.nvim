local M = {}

local Process = require("anvil.process")
local git = require("anvil.lib.git")
local input = require("anvil.lib.input")
local notification = require("anvil.lib.notification")
local config = require("anvil.config")

local function git_cmd(args)
  local cmd = { config.values.git_executable or "git" }
  vim.list_extend(cmd, args)

  local proc = Process.new {
    cmd = cmd,
    cwd = git.repo.worktree_root,
    on_error = function()
      return true
    end,
  }

  return proc:spawn_async()
end

local function current_or_prompt_commit(popup)
  local commit = popup:get_env("commit")
  if commit and commit ~= "" then
    return commit
  end

  return input.get_user_input("Commit", { default = "HEAD" })
end

function M.edit(popup)
  local commit = current_or_prompt_commit(popup)
  if not commit then
    return
  end

  git_cmd { "notes", "edit", commit }
end

function M.add(popup)
  local commit = current_or_prompt_commit(popup)
  if not commit then
    return
  end

  local message = input.get_user_input("Note")
  if not message then
    return
  end

  local result = git_cmd { "notes", "add", "-m", message, commit }
  if result and result:success() then
    notification.info(("Added note to %s"):format(commit))
  end
end

function M.append(popup)
  local commit = current_or_prompt_commit(popup)
  if not commit then
    return
  end

  local message = input.get_user_input("Append note")
  if not message then
    return
  end

  local result = git_cmd { "notes", "append", "-m", message, commit }
  if result and result:success() then
    notification.info(("Appended note to %s"):format(commit))
  end
end

function M.show(popup)
  local commit = current_or_prompt_commit(popup)
  if not commit then
    return
  end

  git_cmd { "notes", "show", commit }
end

function M.remove(popup)
  local commit = current_or_prompt_commit(popup)
  if not commit or not input.get_permission(("Remove note from %s?"):format(commit)) then
    return
  end

  local result = git_cmd { "notes", "remove", commit }
  if result and result:success() then
    notification.info(("Removed note from %s"):format(commit))
  end
end

function M.prune()
  local result = git_cmd { "notes", "prune" }
  if result and result:success() then
    notification.info("Pruned notes")
  end
end

function M.merge()
  local ref = input.get_user_input("Merge notes ref", { default = "refs/notes/commits" })
  if not ref then
    return
  end

  local result = git_cmd { "notes", "merge", ref }
  if result and result:success() then
    notification.info(("Merged notes from %s"):format(ref))
  end
end

return M
