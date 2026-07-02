local git = require("anvil.lib.git")
local util = require("anvil.lib.util")

---@class AnvilGitCherry
local M = {}

function M.list(upstream, head)
  local result = git.cli.cherry.verbose.args(upstream, head).call({ hidden = true }).stdout
  return util.reverse(util.map(result, function(cherry)
    local status, oid, subject = cherry:match("([%+%-]) (%x+) (.*)")
    return { status = status, oid = oid, subject = subject }
  end))
end

return M
