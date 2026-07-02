local logger = require("neogit.logger")

---Local forge topic store. Forge is "local-first": the status buffer renders
---from disk, and syncing with the forge happens explicitly. sqlite.lua is used
---when available, with the original JSON file store as the fallback.
---@class NeogitForgeStore
local M = {}

---@class ForgeTopics
---@field pullreqs table[]
---@field issues table[]
---@field discussions table[]
---@field notifications table[]
---@field synced_at string|nil ISO8601 timestamp of the last successful pull

---@param repo ForgeRepo
---@return string
local function repo_key(repo)
  return ("%s/%s/%s"):format(repo.host, repo.owner, repo.name)
end

local function store_dir()
  local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "neogit", "forge")
  vim.fn.mkdir(dir, "p")
  return dir
end

---@param repo ForgeRepo
---@return string
local function json_store_path(repo)
  return vim.fs.joinpath(store_dir(), vim.fn.sha256(repo_key(repo)) .. ".json")
end

local function sqlite_store_path()
  return vim.fs.joinpath(store_dir(), "forge.sqlite3")
end

local function sql_quote(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local sqlite_db
local sqlite_checked = false

local function sqlite()
  if sqlite_checked then
    return sqlite_db
  end

  sqlite_checked = true

  local ok, sqlite_mod = pcall(require, "sqlite")
  if not ok or type(sqlite_mod) ~= "table" or type(sqlite_mod.open) ~= "function" then
    return nil
  end

  local open_ok, db = pcall(function()
    return sqlite_mod:open(sqlite_store_path())
  end)
  if not open_ok or not db or type(db.eval) ~= "function" then
    logger.debug("[FORGE] sqlite.lua unavailable, using JSON forge store")
    return nil
  end

  local schema_ok, err = pcall(function()
    db:eval([[
      CREATE TABLE IF NOT EXISTS forge_store (
        repo TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ]])
  end)
  if not schema_ok then
    logger.error("[FORGE] Failed to initialize SQLite forge store: " .. tostring(err))
    return nil
  end

  sqlite_db = db
  return sqlite_db
end

function M.backend()
  return sqlite() and "sqlite" or "json"
end

---Load the raw stored data for a repository.
---@param repo ForgeRepo
---@return table|nil
function M.load(repo)
  local db = sqlite()
  if db then
    local ok, rows = pcall(function()
      return db:eval(("SELECT data FROM forge_store WHERE repo = %s LIMIT 1"):format(sql_quote(repo_key(repo))))
    end)
    if ok and type(rows) == "table" and rows[1] and rows[1].data then
      local decode_ok, decoded = pcall(vim.json.decode, rows[1].data, { luanil = { object = true, array = true } })
      if decode_ok and type(decoded) == "table" then
        return decoded
      end
      logger.error("[FORGE] Failed to decode SQLite store row for: " .. repo_key(repo))
    elseif not ok then
      logger.error("[FORGE] Failed to read SQLite forge store: " .. tostring(rows))
    end

    return nil
  end

  local path = json_store_path(repo)

  local fd = io.open(path, "r")
  if not fd then
    return nil
  end

  local content = fd:read("*a")
  fd:close()

  if not content or content == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= "table" then
    logger.error("[FORGE] Failed to decode store file: " .. path)
    return nil
  end

  return decoded
end

---Persist data for a repository.
---@param repo ForgeRepo
---@param data table
---@return boolean success
function M.save(repo, data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    logger.error("[FORGE] Failed to encode store data: " .. tostring(encoded))
    return false
  end

  local db = sqlite()
  if db then
    local saved, err = pcall(function()
      db:eval(
        ("INSERT INTO forge_store(repo, data, updated_at) VALUES(%s, %s, %s) "
          .. "ON CONFLICT(repo) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at"):format(
          sql_quote(repo_key(repo)),
          sql_quote(encoded),
          sql_quote(os.date("!%Y-%m-%dT%H:%M:%SZ"))
        )
      )
    end)
    if not saved then
      logger.error("[FORGE] Failed to write SQLite forge store: " .. tostring(err))
      return false
    end

    return true
  end

  local path = json_store_path(repo)

  local fd = io.open(path, "w")
  if not fd then
    logger.error("[FORGE] Failed to open store file for writing: " .. path)
    return false
  end

  fd:write(encoded)
  fd:close()

  return true
end

---Read the stored topics for a repository, with safe defaults when the
---store is empty or missing.
---@param repo ForgeRepo
---@return ForgeTopics
function M.get_topics(repo)
  local data = M.load(repo) or {}

  return {
    pullreqs = type(data.pullreqs) == "table" and data.pullreqs or {},
    issues = type(data.issues) == "table" and data.issues or {},
    discussions = type(data.discussions) == "table" and data.discussions or {},
    notifications = type(data.notifications) == "table" and data.notifications or {},
    synced_at = data.synced_at,
  }
end

---@param repo ForgeRepo
---@param topic table
---@return boolean success
function M.save_topic(repo, topic)
  local data = M.load(repo) or {}
  local key = topic.kind == "pullreq" and "pullreqs" or topic.kind == "discussion" and "discussions" or "issues"
  local topics = type(data[key]) == "table" and data[key] or {}
  local replaced = false

  for i, existing in ipairs(topics) do
    if existing.number == topic.number then
      topics[i] = vim.tbl_deep_extend("force", existing, topic)
      replaced = true
      break
    end
  end

  if not replaced then
    table.insert(topics, topic)
  end

  data[key] = topics
  data.synced_at = data.synced_at or os.date("!%Y-%m-%dT%H:%M:%SZ")
  data.topic_synced_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

  return M.save(repo, data)
end

---@param repo ForgeRepo
---@param topic table
---@param attrs table
---@return boolean success
function M.update_topic(repo, topic, attrs)
  if not topic or not topic.kind or not topic.number then
    return false
  end

  return M.save_topic(repo, vim.tbl_deep_extend("force", topic, attrs, {
    mark_updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }))
end

---@param repo ForgeRepo
---@param notifications table[]
---@return boolean success
function M.save_notifications(repo, notifications)
  local data = M.load(repo) or {}
  data.notifications = notifications
  data.notifications_synced_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  return M.save(repo, data)
end

---@param repo ForgeRepo
---@param id string
---@param attrs table
---@return boolean success
function M.update_notification(repo, id, attrs)
  local data = M.load(repo) or {}
  local notifications = type(data.notifications) == "table" and data.notifications or {}
  local replaced = false

  for i, item in ipairs(notifications) do
    if tostring(item.id) == tostring(id) then
      notifications[i] = vim.tbl_deep_extend("force", item, attrs)
      replaced = true
      break
    end
  end

  if not replaced then
    table.insert(notifications, vim.tbl_deep_extend("force", { id = id }, attrs))
  end

  data.notifications = notifications
  data.notifications_synced_at = data.notifications_synced_at or os.date("!%Y-%m-%dT%H:%M:%SZ")
  data.notification_state_updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

  return M.save(repo, data)
end

return M
