local api = vim.api

api.nvim_create_user_command("Anvil", function(o)
  local anvil = require("anvil")
  anvil.open(require("anvil.lib.util").parse_command_args(o.fargs))
end, {
  nargs = "*",
  desc = "Open Anvil",
  complete = function(arglead)
    local anvil = require("anvil")
    return anvil.complete(arglead)
  end,
})

api.nvim_create_user_command("AnvilResetState", function()
  require("anvil.lib.state")._reset()
end, { nargs = "*", desc = "Reset any saved flags" })

api.nvim_create_user_command("AnvilLogCurrent", function(args)
  local action = require("anvil").action
  local path = vim.fn.expand(args.fargs[1] or "%")

  if args.range > 0 then
    action("log", "log_current", { "-L" .. args.line1 .. "," .. args.line2 .. ":" .. path })()
  else
    action("log", "log_current", { "--", path })()
  end
end, {
  nargs = "?",
  desc = "Open git log (current) for specified file, or current file if unspecified. Optionally accepts a range.",
  range = "%",
  complete = "file",
})

api.nvim_create_user_command("AnvilCommit", function(args)
  local commit = args.fargs[1] or "HEAD"
  local CommitViewBuffer = require("anvil.buffers.commit_view")
  CommitViewBuffer.new(commit):open()
end, {
  nargs = "?",
  desc = "Open git commit view for specified commit, or HEAD",
})
