local M = {}

local command = require("neogit.popups._git_command")
local input = require("neogit.lib.input")

function M.mergetool()
  local tool = input.get_user_input("Mergetool")
  local args = { "mergetool" }
  if tool then
    vim.list_extend(args, { "--tool", tool })
  end
  command.run(args, { refresh = "mergetool" })
end

function M.gui_mergetool()
  command.run({ "mergetool", "--gui" }, { refresh = "mergetool_gui" })
end

function M.check()
  command.run({ "diff", "--check" }, { refresh = false })
end

return M
