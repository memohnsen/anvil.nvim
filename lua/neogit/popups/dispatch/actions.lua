local M = {}

local function open(name)
  return function()
    require("neogit.popups." .. name).create {}
  end
end

M.status = function()
  require("neogit").open()
end

M.commit = open("commit")
M.diff = open("diff")
M.log = open("log")
M.branch = open("branch")
M.remote = open("remote")
M.stash = open("stash")
M.forge = open("forge")
M.run = open("run")
M.patch = open("patch")
M.submodule = open("submodule")
M.repos = open("repos")

return M
