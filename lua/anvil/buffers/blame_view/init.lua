local Buffer = require("anvil.lib.buffer")
local ui = require("anvil.buffers.blame_view.ui")
local git = require("anvil.lib.git")
local notification = require("anvil.lib.notification")
local status_maps = require("anvil.config").get_reversed_status_maps()

local api = vim.api

---@class BlameViewBuffer
---@field file string file path relative to the worktree root
---@field rev string|nil revision being blamed; nil for the working tree
---@field hunks BlameHunk[]
---@field buffer Buffer
---@field heading_lines number[] sorted buffer line numbers of hunk headings
---@field hunk_by_heading table<number, BlameHunk>
---@field return_win number|nil window to return to on close
---@field return_buf number|nil buffer to return to on close
local M = {
  instance = nil,
}

---Makes a path relative to the worktree root.
---@param path string absolute or relative path
---@return string|nil relative path, or nil if outside the worktree
local function relativize(path)
  local root = git.repo.worktree_root
  if not root or root == "" then
    return nil
  end

  if not path:match("^/") and not path:match("^%a:[/\\]") then
    return path
  end

  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local nroot = vim.fs.normalize(root)

  if abs:sub(1, #nroot + 1) == nroot .. "/" then
    return abs:sub(#nroot + 2)
  end

  return nil
end

---Creates a new BlameViewBuffer
---@param file_path string path of the file to blame (absolute, or relative to the worktree root)
---@param rev string|nil revision to blame at; nil blames the working tree file
---@return BlameViewBuffer
function M.new(file_path, rev)
  local instance = {
    file = file_path,
    rev = rev,
    hunks = {},
    heading_lines = {},
    hunk_by_heading = {},
    buffer = nil,
  }

  setmetatable(instance, { __index = M })

  return instance
end

---@return boolean
function M.is_open()
  return (M.instance and M.instance.buffer and M.instance.buffer:is_visible()) == true
end

function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end

  M.instance = nil
end

---Builds the buffer-line index for the current hunks.
---Layout is deterministic: each hunk renders one heading line followed by
---its content lines, so buffer positions can be computed directly.
---@param self BlameViewBuffer
local function build_index(self)
  self.heading_lines = {}
  self.hunk_by_heading = {}

  local line = 1
  for _, hunk in ipairs(self.hunks) do
    table.insert(self.heading_lines, line)
    self.hunk_by_heading[line] = hunk
    line = line + 1 + hunk.count
  end
end

---@param self BlameViewBuffer
---@param line number buffer line
---@return BlameHunk|nil
---@return number|nil heading buffer line of the hunk
local function hunk_for_line(self, line)
  local found, found_heading
  for _, heading in ipairs(self.heading_lines) do
    if heading > line then
      break
    end

    found, found_heading = self.hunk_by_heading[heading], heading
  end

  return found, found_heading
end

---@param self BlameViewBuffer
---@param line number buffer line
---@return number file line (1-indexed line in the blamed file content)
local function file_line_for_buffer_line(self, line)
  local hunk, heading = hunk_for_line(self, line)
  if not hunk or not heading then
    return 1
  end

  if line == heading then
    return hunk.start_line
  end

  return math.min(hunk.start_line + (line - heading - 1), hunk.start_line + hunk.count - 1)
end

---@param self BlameViewBuffer
---@param file_line number
---@return number buffer line
local function buffer_line_for_file_line(self, file_line)
  local offset = 0
  for _, hunk in ipairs(self.hunks) do
    if hunk.start_line <= file_line then
      offset = offset + 1
    else
      break
    end
  end

  return file_line + offset
end

---Runs blame and re-renders the buffer for a new revision/file
---("blame from blame", magit-style).
---@param rev string|nil
---@param file string path relative to the worktree root
function M:reblame(rev, file)
  local hunks, err = git.blame.run(file, rev)
  if not hunks then
    notification.error(("Cannot blame %s at %s: %s"):format(file, rev or "worktree", err))
    return
  end

  if #hunks == 0 then
    notification.warn(("No lines to blame in %s at %s"):format(file, rev or "worktree"))
    return
  end

  self.rev = rev
  self.file = file
  self.hunks = hunks
  build_index(self)

  self.buffer.ui:render(unpack(ui.View(self.hunks)))
  self.buffer:win_call(vim.cmd, "normal! gg")

  notification.info(("Blaming %s at %s"):format(file, rev or "worktree"))
end

---Reblames at the commit before the hunk's commit
---@param self BlameViewBuffer
---@param hunk BlameHunk
local function blame_before(self, hunk)
  local rev, file
  if hunk.uncommitted then
    rev = "HEAD"
    file = self.file
  elseif hunk.previous_sha then
    rev = hunk.previous_sha
    file = hunk.previous_filename or self.file
  else
    rev = hunk.oid .. "^"
    file = (hunk.filename ~= "" and hunk.filename) or self.file
  end

  self:reblame(rev, file)
end

---Closes the blame buffer and returns to the original window/position
---@param self BlameViewBuffer
local function close_and_return(self)
  local file_line = file_line_for_buffer_line(self, self.buffer:cursor_line())
  local return_win, return_buf = self.return_win, self.return_buf

  self:close()

  if return_win and api.nvim_win_is_valid(return_win) then
    api.nvim_set_current_win(return_win)
  end

  if return_buf and api.nvim_buf_is_valid(return_buf) and api.nvim_buf_is_loaded(return_buf) then
    api.nvim_set_current_buf(return_buf)
    pcall(api.nvim_win_set_cursor, 0, { file_line, 0 })
  end
end

---Opens the BlameViewBuffer. Notifies and aborts cleanly if the file cannot
---be blamed (untracked, outside the repo, missing in the given revision, or
---empty).
---@param kind string|nil defaults to "replace" (blame in place, like magit)
---@return BlameViewBuffer
function M:open(kind)
  kind = kind or "replace"

  local file = relativize(self.file)
  if not file then
    notification.error(("%q is not inside the git worktree"):format(self.file))
    return self
  end

  local hunks, err = git.blame.run(file, self.rev)
  if not hunks then
    notification.error(("Cannot blame %s: %s"):format(file, err))
    return self
  end

  if #hunks == 0 then
    notification.warn(("No lines to blame in %s"):format(file))
    return self
  end

  if M.is_open() then
    M.instance:close()
  end

  M.instance = self

  self.file = file
  self.hunks = hunks
  build_index(self)

  self.return_win = api.nvim_get_current_win()
  self.return_buf = api.nvim_get_current_buf()

  local origin_line
  if not self.rev and api.nvim_buf_get_name(self.return_buf) ~= "" then
    origin_line = api.nvim_win_get_cursor(self.return_win)[1]
  end

  self.buffer = Buffer.create {
    name = "AnvilBlameView",
    filetype = "AnvilBlameView",
    kind = kind,
    context_highlight = true,
    mappings = {
      n = {
        ["<cr>"] = function()
          local hunk = hunk_for_line(self, self.buffer:cursor_line())
          if not hunk then
            return
          end

          if hunk.uncommitted then
            notification.info("These lines have not been committed yet")
            return
          end

          require("anvil.buffers.commit_view").new(hunk.oid):open()
        end,
        ["b"] = function()
          local hunk = hunk_for_line(self, self.buffer:cursor_line())
          if hunk then
            blame_before(self, hunk)
          end
        end,
        ["B"] = function()
          local hunk = hunk_for_line(self, self.buffer:cursor_line())
          if hunk then
            blame_before(self, hunk)
          end
        end,
        ["n"] = function()
          local line = self.buffer:cursor_line()
          for _, heading in ipairs(self.heading_lines) do
            if heading > line then
              self.buffer:move_cursor(heading)
              return
            end
          end
        end,
        ["p"] = function()
          local line = self.buffer:cursor_line()
          for i = #self.heading_lines, 1, -1 do
            if self.heading_lines[i] < line then
              self.buffer:move_cursor(self.heading_lines[i])
              return
            end
          end
        end,
        [status_maps["YankSelected"]] = function()
          local hunk = hunk_for_line(self, self.buffer:cursor_line())
          if hunk and not hunk.uncommitted then
            local yank = ("'%s'"):format(hunk.oid)
            vim.cmd.let("@+=" .. yank)
            vim.cmd.echo(yank)
          end
        end,
        [status_maps["Close"]] = function()
          close_and_return(self)
        end,
        ["<esc>"] = function()
          close_and_return(self)
        end,
      },
    },
    render = function()
      return ui.View(self.hunks)
    end,
    after = function(buffer)
      if origin_line then
        pcall(buffer.move_cursor, buffer, buffer_line_for_file_line(self, origin_line))
      end
    end,
  }

  return self
end

return M
