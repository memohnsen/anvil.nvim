local M = {}

local command = require("neogit.popups._git_command")
local input = require("neogit.lib.input")

function M.create()
  local file = input.get_user_input("Bundle file", { completion = "file" })
  if not file then
    return
  end

  local revs = input.get_user_input("Revisions", { default = "HEAD" })
  if revs then
    command.run({ "bundle", "create", file, unpack(vim.split(revs, "%s+")) }, { refresh = false })
  end
end

function M.verify()
  local file = input.get_user_input("Verify bundle", { completion = "file" })
  if file then
    command.run({ "bundle", "verify", file }, { refresh = false })
  end
end

function M.list_heads()
  local file = input.get_user_input("List heads in bundle", { completion = "file" })
  if file then
    command.run({ "bundle", "list-heads", file }, { refresh = false })
  end
end

function M.unbundle()
  local file = input.get_user_input("Unbundle", { completion = "file" })
  if file then
    command.run({ "bundle", "unbundle", file }, { refresh = false })
  end
end

return M
