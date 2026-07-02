local M = {}

local command = require("anvil.popups._git_command")
local input = require("anvil.lib.input")

function M.current()
  command.run({ "shortlog", "-sn", "HEAD" }, { refresh = false })
end

function M.all()
  command.run({ "shortlog", "-sn", "--all" }, { refresh = false })
end

function M.range()
  local range = input.get_user_input("Shortlog range", { default = "HEAD" })
  if range then
    command.run({ "shortlog", "-sn", range }, { refresh = false })
  end
end

return M
