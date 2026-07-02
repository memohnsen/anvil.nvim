local M = {}

local input = require("anvil.lib.input")

function M.list()
  local root = input.get_user_input("Repository root", {
    completion = "dir",
    default = vim.uv.cwd(),
  })
  if root then
    require("anvil.buffers.repos_view").new(root):open()
  end
end

return M
