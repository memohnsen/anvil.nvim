local notification = require("neogit.lib.notification")
local logger = require("neogit.logger")

---@class ForgeRepo
---@field host string
---@field owner string
---@field name string

---@class NeogitForgeClient
local M = {}

---@type boolean|nil
local gh_available = nil

---@type boolean|nil
local gh_authed = nil

---@type table<string, ForgeRepo|false>
local repo_cache = {}

---@return string|nil
local function worktree_root()
  local ok, git = pcall(require, "neogit.lib.git")
  if ok and git.repo and git.repo.worktree_root then
    return git.repo.worktree_root
  end

  return vim.uv.cwd()
end

---Is the `gh` executable available? Cached after first call.
---@return boolean
function M.available()
  if gh_available == nil then
    gh_available = vim.fn.executable("gh") == 1
  end

  return gh_available
end

---Is `gh` authenticated? Cached after first call.
---@return boolean
function M.authed()
  if not M.available() then
    return false
  end

  if gh_authed == nil then
    local ok, proc = pcall(vim.system, { "gh", "auth", "status" }, { text = true })
    if not ok then
      gh_authed = false
    else
      local result = proc:wait(10000)
      gh_authed = result ~= nil and result.code == 0
    end
  end

  return gh_authed
end

---Parse a git remote url into a ForgeRepo, or nil for non-GitHub remotes.
---@param url string
---@return ForgeRepo|nil
function M.parse_url(url)
  if not url or url == "" then
    return nil
  end

  local host, path

  -- scp-like ssh: git@github.com:owner/name.git
  host, path = url:match("^[%w%-_%.]+@([^:/]+):(.+)$")

  if not host then
    -- ssh://git@github.com/owner/name.git (optionally with port)
    host, path = url:match("^ssh://[^@/]+@([^:/]+):?%d*/(.+)$")
  end

  if not host then
    -- https://github.com/owner/name(.git)
    host, path = url:match("^https?://([^:/]+):?%d*/(.+)$")
  end

  if not host or not path then
    return nil
  end

  if host ~= "github.com" and not host:find("github", 1, true) then
    return nil
  end

  path = path:gsub("%.git$", ""):gsub("/+$", "")

  local owner, name = path:match("^([^/]+)/([^/]+)$")
  if not owner or not name then
    return nil
  end

  return { host = host, owner = owner, name = name }
end

---@param remote string
---@param cwd string
---@return string|nil
local function remote_url(remote, cwd)
  local ok, proc = pcall(vim.system, { "git", "remote", "get-url", remote }, { text = true, cwd = cwd })
  if not ok then
    return nil
  end

  local result = proc:wait(5000)
  if not result or result.code ~= 0 then
    return nil
  end

  return vim.trim(result.stdout or "")
end

---Detect the GitHub repository for the current worktree, checking the
---"origin" remote first and falling back to "upstream".
---@return ForgeRepo|nil
function M.get_repo()
  local cwd = worktree_root()
  if not cwd then
    return nil
  end

  local cached = repo_cache[cwd]
  if cached ~= nil then
    return cached or nil
  end

  for _, remote in ipairs { "origin", "upstream" } do
    local url = remote_url(remote, cwd)
    if url and url ~= "" then
      local repo = M.parse_url(url)
      if repo then
        repo_cache[cwd] = repo
        return repo
      end
    end
  end

  repo_cache[cwd] = false
  return nil
end

---@param out vim.SystemCompleted
---@return table|nil data
---@return string|nil err
local function parse_response(out)
  if out.code ~= 0 then
    local err = vim.trim(out.stderr or "")
    if err == "" then
      err = ("gh exited with code %d"):format(out.code)
    end

    return nil, err
  end

  if vim.trim(out.stdout or "") == "" then
    return {}, nil
  end

  local ok, decoded = pcall(vim.json.decode, out.stdout or "", { luanil = { object = true, array = true } })
  if not ok then
    return nil, "Failed to decode gh response: " .. tostring(decoded)
  end

  if type(decoded) == "table" and decoded.errors then
    local messages = {}
    for _, e in ipairs(decoded.errors) do
      table.insert(messages, e.message or vim.inspect(e))
    end

    return nil, table.concat(messages, "\n")
  end

  return decoded, nil
end

---@param args string[]
---@param cb fun(data: table|nil, err: string|nil)
---@param opts table|nil
local function run(args, cb, opts)
  if not M.available() then
    vim.schedule(function()
      notification.error("Forge: 'gh' executable not found")
      cb(nil, "gh not found")
    end)
    return
  end

  logger.debug("[FORGE] Running: " .. table.concat(args, " "))

  local ok, err = pcall(
    vim.system,
    args,
    vim.tbl_extend("force", { text = true, cwd = worktree_root() }, opts or {}),
    vim.schedule_wrap(function(out)
      local data, e = parse_response(out)
      if e then
        notification.error("Forge: " .. e)
      end

      cb(data, e)
    end)
  )

  if not ok then
    vim.schedule(function()
      notification.error("Forge: failed to spawn gh: " .. tostring(err))
      cb(nil, tostring(err))
    end)
  end
end

---Run a GraphQL query via `gh api graphql`, asynchronously.
---String variables are passed with -f, everything else with -F.
---Nested variables are sent as a JSON request body because gh field flags
---cannot represent GraphQL input objects and arrays reliably.
---@param query string
---@param variables table<string, any>|nil
---@param cb fun(data: table|nil, err: string|nil) Called with the "data" payload
function M.graphql(query, variables, cb)
  local has_complex_variable = false
  for _, v in pairs(variables or {}) do
    if type(v) == "table" then
      has_complex_variable = true
      break
    end
  end

  if has_complex_variable then
    run(
      { "gh", "api", "graphql", "--input", "-" },
      function(data, err)
        if err then
          cb(nil, err)
        else
          cb(data and data.data or nil, nil)
        end
      end,
      {
        stdin = vim.json.encode {
          query = query,
          variables = variables or {},
        },
      }
    )
    return
  end

  local args = { "gh", "api", "graphql", "-f", "query=" .. query }

  for k, v in pairs(variables or {}) do
    if type(v) == "string" then
      table.insert(args, "-f")
      table.insert(args, ("%s=%s"):format(k, v))
    else
      table.insert(args, "-F")
      table.insert(args, ("%s=%s"):format(k, tostring(v)))
    end
  end

  run(args, function(data, err)
    if err then
      cb(nil, err)
    else
      cb(data and data.data or nil, nil)
    end
  end)
end

---Call a REST endpoint via `gh api`, asynchronously.
---@param path string e.g. "repos/{owner}/{repo}/issues"
---@param opts { method: string|nil, fields: table<string, string>|nil, cb: fun(data: table|nil, err: string|nil) }
function M.rest(path, opts)
  opts = opts or {}

  local args = { "gh", "api" }

  if opts.method then
    table.insert(args, "--method")
    table.insert(args, opts.method)
  end

  table.insert(args, path)

  for k, v in pairs(opts.fields or {}) do
    table.insert(args, "-f")
    table.insert(args, ("%s=%s"):format(k, v))
  end

  run(args, opts.cb or function() end)
end

---Run a non-JSON gh command asynchronously.
---@param args string[] The full command, usually starting with `gh`.
---@param cb fun(success: boolean, err: string|nil)|nil
function M.command(args, cb)
  cb = cb or function() end

  if not M.available() then
    vim.schedule(function()
      notification.error("Forge: 'gh' executable not found")
      cb(false, "gh not found")
    end)
    return
  end

  logger.debug("[FORGE] Running: " .. table.concat(args, " "))

  local ok, err = pcall(
    vim.system,
    args,
    { text = true, cwd = worktree_root() },
    vim.schedule_wrap(function(out)
      if out.code ~= 0 then
        local message = vim.trim(out.stderr or "")
        if message == "" then
          message = ("gh exited with code %d"):format(out.code)
        end

        notification.error("Forge: " .. message)
        cb(false, message)
      else
        cb(true, nil)
      end
    end)
  )

  if not ok then
    vim.schedule(function()
      notification.error("Forge: failed to spawn gh: " .. tostring(err))
      cb(false, tostring(err))
    end)
  end
end

---Reset cached availability/auth/repo detection (mostly for testing).
function M.reset_cache()
  gh_available = nil
  gh_authed = nil
  repo_cache = {}
end

return M
