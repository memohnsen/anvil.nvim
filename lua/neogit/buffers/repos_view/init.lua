local Buffer = require("neogit.lib.buffer")

local M = {}
M.__index = M

local function scan(root)
  local repos = {}

  local function visit(dir, depth)
    if depth > 4 then
      return
    end

    local git_dir = vim.fs.joinpath(dir, ".git")
    if vim.uv.fs_stat(git_dir) then
      table.insert(repos, dir)
      return
    end

    local iter = vim.fs.dir(dir)
    if not iter then
      return
    end

    for name, type in iter do
      if type == "directory" and not name:match("^%.") then
        visit(vim.fs.joinpath(dir, name), depth + 1)
      end
    end
  end

  visit(root, 0)
  table.sort(repos)
  return repos
end

function M.new(root)
  return setmetatable({
    root = root or vim.uv.cwd(),
    repos = {},
    buffer = nil,
  }, M)
end

function M:open(kind)
  self.repos = scan(self.root)
  self.buffer = Buffer.create {
    name = "NeogitRepos",
    filetype = "NeogitRepos",
    kind = kind or "split",
    disable_line_numbers = true,
    mappings = {
      n = {
        ["<cr>"] = function(buffer)
          local repo = self.repos[vim.fn.line(".") - 3]
          if repo then
            buffer:close()
            require("neogit").open { cwd = repo }
          end
        end,
        ["q"] = function(buffer)
          buffer:close()
        end,
        ["<esc>"] = function(buffer)
          buffer:close()
        end,
      },
    },
    initialize = function(buffer)
      local title = "Neogit Repositories"
      local lines = { title, string.rep("=", #title), "" }
      vim.list_extend(lines, self.repos)

      buffer:set_buffer_option("modifiable", true)
      buffer:set_lines(0, -1, false, lines)
      buffer:set_buffer_option("modifiable", false)
    end,
  }

  return self
end

return M
