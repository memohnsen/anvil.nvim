local M = {}

local command = require("anvil.popups._git_command")
local input = require("anvil.lib.input")

function M.init(popup)
  local args = { "sparse-checkout", "init" }
  vim.list_extend(args, popup:get_arguments())
  command.run(args, { refresh = "sparse_checkout_init" })
end

function M.disable()
  command.run({ "sparse-checkout", "disable" }, { refresh = "sparse_checkout_disable" })
end

function M.set()
  local patterns = input.get_user_input("Sparse patterns")
  if patterns then
    command.run({ "sparse-checkout", "set", unpack(vim.split(patterns, "%s+")) }, { refresh = "sparse_checkout_set" })
  end
end

function M.add()
  local patterns = input.get_user_input("Add sparse patterns")
  if patterns then
    command.run({ "sparse-checkout", "add", unpack(vim.split(patterns, "%s+")) }, { refresh = "sparse_checkout_add" })
  end
end

function M.reapply()
  command.run({ "sparse-checkout", "reapply" }, { refresh = "sparse_checkout_reapply" })
end

function M.list()
  command.run({ "sparse-checkout", "list" }, { refresh = false })
end

return M
