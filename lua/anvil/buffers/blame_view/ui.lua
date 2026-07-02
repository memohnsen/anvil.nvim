local Ui = require("anvil.lib.ui")

local col = Ui.col
local row = Ui.row
local text = Ui.text

local M = {}

---Formats a unix timestamp as a magit-like relative date ("3 days ago")
---@param timestamp number
---@return string
function M.relative_date(timestamp)
  local diff = os.time() - timestamp
  if diff < 0 then
    diff = 0
  end

  local units = {
    { 60 * 60 * 24 * 365, "year" },
    { 60 * 60 * 24 * 30, "month" },
    { 60 * 60 * 24 * 7, "week" },
    { 60 * 60 * 24, "day" },
    { 60 * 60, "hour" },
    { 60, "minute" },
  }

  for _, unit in ipairs(units) do
    local amount = math.floor(diff / unit[1])
    if amount >= 1 then
      return ("%d %s%s ago"):format(amount, unit[2], amount > 1 and "s" or "")
    end
  end

  return "just now"
end

---Renders the heading line for a blame hunk:
---  "shortsha author date summary"
---@param hunk BlameHunk
---@return table
local function HunkHeading(hunk)
  local children
  if hunk.uncommitted then
    children = {
      text(hunk.abbrev, { highlight = "AnvilObjectId" }),
      text(" "),
      text("Uncommitted changes", { highlight = "AnvilSubtleText" }),
    }
  else
    children = {
      text(hunk.abbrev, { highlight = "AnvilObjectId" }),
      text(" "),
      text(hunk.author, { highlight = "AnvilGraphAuthor" }),
      text(" "),
      text(M.relative_date(hunk.author_time), { highlight = "AnvilSubtleText" }),
      text(" "),
      text(hunk.summary),
    }
  end

  return row(children, { line_hl = "AnvilDiffHeader" })
end

---Renders a blame hunk: heading line followed by the hunk's file lines.
---@param hunk BlameHunk
---@return table
M.Hunk = function(hunk)
  local children = { HunkHeading(hunk) }

  for _, line in ipairs(hunk.lines) do
    table.insert(children, row { text(line) })
  end

  return col(children, {
    tag = "BlameHunk",
    oid = hunk.oid,
    hunk = hunk,
  })
end

---@param hunks BlameHunk[]
---@return table
function M.View(hunks)
  local children = {}
  for _, hunk in ipairs(hunks) do
    table.insert(children, M.Hunk(hunk))
  end

  return children
end

return M
