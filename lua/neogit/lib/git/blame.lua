local git = require("neogit.lib.git")
local process = require("neogit.process")
local config = require("neogit.config")

---@class NeogitGitBlame
local M = {}

---The all-zeros sha used by `git blame` for lines not yet committed
M.NULL_SHA = string.rep("0", 40)

---@param oid string
---@return boolean
function M.is_uncommitted(oid)
  return oid == M.NULL_SHA
end

---@class BlameHunk
---@field oid string full sha of the commit that introduced these lines (all zeros when uncommitted)
---@field abbrev string abbreviated sha
---@field author string author name ("Uncommitted changes" for the null sha)
---@field author_mail string author email, without angle brackets
---@field author_time number author time as unix timestamp
---@field summary string commit summary line
---@field previous_sha string|nil sha of the previous commit touching this file, if any
---@field previous_filename string|nil filename in the previous commit (differs on rename)
---@field filename string filename this hunk was blamed from (differs from the input path on rename)
---@field start_line number 1-indexed first line of this hunk in the blamed file content
---@field count number number of consecutive lines in this hunk
---@field lines string[] the file content lines of this hunk
---@field uncommitted boolean true when the lines are not yet committed

---Parses `git blame --porcelain` output into per-line records, then groups
---consecutive lines belonging to the same commit into hunks (magit-style).
---@param raw string[] raw stdout lines from `git blame --porcelain`
---@return BlameHunk[]
function M.parse(raw)
  local commits = {} ---@type table<string, table>
  local entries = {} ---@type { oid: string, final: number, content: string }[]

  local idx = 1
  while idx <= #raw do
    local line = raw[idx]
    local oid, _, final = line:match("^(%x+) (%d+) (%d+)")

    if oid and #oid == 40 then
      local info = commits[oid]
      if not info then
        info = {}
        commits[oid] = info
      end

      idx = idx + 1

      -- Header lines follow until the actual content line, which is prefixed
      -- with a tab. Headers are only emitted the first time a commit is seen.
      while idx <= #raw and raw[idx]:sub(1, 1) ~= "\t" do
        local header = raw[idx]
        local key, value = header:match("^([%w%-]+)%s?(.*)$")

        if key == "author" then
          info.author = value
        elseif key == "author-mail" then
          info.author_mail = value:match("^<(.*)>$") or value
        elseif key == "author-time" then
          info.author_time = tonumber(value)
        elseif key == "summary" then
          info.summary = value
        elseif key == "previous" then
          info.previous_sha, info.previous_filename = value:match("^(%x+)%s(.+)$")
        elseif key == "filename" then
          info.filename = value
        end

        idx = idx + 1
      end

      local content = raw[idx] and raw[idx]:sub(2) or ""
      table.insert(entries, { oid = oid, final = tonumber(final), content = content })

      idx = idx + 1
    else
      -- Unexpected line; skip defensively rather than erroring
      idx = idx + 1
    end
  end

  -- Group consecutive lines of the same commit into hunks
  local hunks = {} ---@type BlameHunk[]
  local current

  for _, entry in ipairs(entries) do
    if current and current.oid == entry.oid then
      current.count = current.count + 1
      table.insert(current.lines, entry.content)
    else
      local info = commits[entry.oid] or {}
      local uncommitted = M.is_uncommitted(entry.oid)

      current = {
        oid = entry.oid,
        abbrev = entry.oid:sub(1, 7),
        author = uncommitted and "Uncommitted changes" or (info.author or "Unknown"),
        author_mail = info.author_mail or "",
        author_time = info.author_time or os.time(),
        summary = uncommitted and "" or (info.summary or ""),
        previous_sha = info.previous_sha,
        previous_filename = info.previous_filename,
        filename = info.filename or "",
        start_line = entry.final,
        count = 1,
        lines = { entry.content },
        uncommitted = uncommitted,
      }

      table.insert(hunks, current)
    end
  end

  return hunks
end

---Runs `git blame --porcelain [rev] -- file` and returns parsed hunks.
---
---`git.cli` only exposes registered subcommands and `blame` isn't one of
---them, so this builds the process directly, mirroring what the cli wrapper
---does internally.
---@param file string path to the file, relative to the worktree root
---@param rev string|nil revision to blame at; nil blames the working tree file
---@return BlameHunk[]|nil hunks nil on failure
---@return string|nil err error message when hunks is nil
function M.run(file, rev)
  local root = git.repo.worktree_root
  if not root or root == "" then
    return nil, "Not inside a git worktree"
  end

  -- stylua: ignore
  local cmd = {
    config.get_git_executable(),
    "--no-pager",
    "--literal-pathspecs",
    "--no-optional-locks",
    "blame",
    "--porcelain",
  }

  if rev and rev ~= "" then
    table.insert(cmd, rev)
  end

  table.insert(cmd, "--")
  table.insert(cmd, file)

  local proc = process.new {
    cmd = cmd,
    cwd = root,
    suppress_console = true,
    git_hook = false,
    user_command = false,
    on_error = function()
      return false
    end,
  }

  local result = proc:spawn_blocking()
  if not result then
    return nil, "git blame failed to run"
  end

  if result.code ~= 0 then
    local stderr = vim.trim(table.concat(result.stderr or {}, "\n"))
    if stderr == "" then
      stderr = ("git blame exited with code %d"):format(result.code)
    end

    return nil, stderr
  end

  return M.parse(result.stdout or {})
end

return M
