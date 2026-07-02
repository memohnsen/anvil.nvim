local Ui = require("anvil.lib.ui")
local Component = require("anvil.lib.ui.component")
local util = require("anvil.lib.util")
local config = require("anvil.config")

local text = Ui.text
local col = Ui.col
local row = Ui.row

local M = {}

---Parses output of `git stash list` and splits elements into table
M.Stash = Component.new(function(stash)
  local label = table.concat({ "stash@{", stash.idx, "}" }, "")
  return col({
    row({
      text.highlight("Comment")(label),
      text(" "),
      text(stash.message),
    }, {
      virtual_text = {
        { " ", "Constant" },
        { config.values.log_date_format ~= nil and stash.date or stash.rel_date, "Special" },
      },
    }),
  }, { oid = label, item = stash })
end)

---@param stashes StashItem[]
---@return table
function M.View(stashes)
  return util.map(stashes, function(stash)
    return M.Stash(stash)
  end)
end

return M
