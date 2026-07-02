local M = {}

local Process = require("anvil.process")
local input = require("anvil.lib.input")
local notification = require("anvil.lib.notification")
local config = require("anvil.config")

local function git_cmd(args, cwd)
  local cmd = { config.values.git_executable or "git" }
  vim.list_extend(cmd, args)

  local proc = Process.new {
    cmd = cmd,
    cwd = cwd or vim.uv.cwd(),
    on_error = function()
      return true
    end,
  }

  return proc:spawn_async()
end

function M.clone(popup)
  local url = input.get_user_input("Clone")
  if not url then
    return
  end

  local directory = input.get_user_input("Directory", { completion = "dir" })
  if not directory then
    return
  end

  local args = { "clone" }
  vim.list_extend(args, popup:get_arguments())
  table.insert(args, url)
  table.insert(args, directory)

  local result = git_cmd(args)
  if result and result:success() then
    notification.info(("Cloned %s into %s"):format(url, directory))
  end
end

return M
