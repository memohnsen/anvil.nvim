local M = {}

local command = require("neogit.popups._git_command")
local input = require("neogit.lib.input")

local function prefix()
  return input.get_user_input("Subtree prefix", { completion = "dir" })
end

function M.add()
  local p = prefix()
  local repo = p and input.get_user_input("Repository")
  local ref = repo and input.get_user_input("Ref", { default = "HEAD" })
  if p and repo and ref then
    command.run({ "subtree", "add", "--prefix", p, repo, ref }, { refresh = "subtree_add" })
  end
end

function M.pull()
  local p = prefix()
  local repo = p and input.get_user_input("Repository")
  local ref = repo and input.get_user_input("Ref", { default = "HEAD" })
  if p and repo and ref then
    command.run({ "subtree", "pull", "--prefix", p, repo, ref }, { refresh = "subtree_pull" })
  end
end

function M.push()
  local p = prefix()
  local repo = p and input.get_user_input("Repository")
  local ref = repo and input.get_user_input("Ref", { default = "HEAD" })
  if p and repo and ref then
    command.run({ "subtree", "push", "--prefix", p, repo, ref }, { refresh = false })
  end
end

function M.split()
  local p = prefix()
  if p then
    command.run({ "subtree", "split", "--prefix", p }, { refresh = false })
  end
end

return M
