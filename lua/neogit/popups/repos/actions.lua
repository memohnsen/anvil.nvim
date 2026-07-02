local M = {}

local input = require("neogit.lib.input")

function M.list()
  local root = input.get_user_input("Repository root", {
    completion = "dir",
    default = vim.uv.cwd(),
  })
  if root then
    require("neogit.buffers.repos_view").new(root):open()
  end
end

return M
