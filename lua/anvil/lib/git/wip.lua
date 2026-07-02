local git = require("anvil.lib.git")
local notification = require("anvil.lib.notification")

local M = {}
local disabled = false

local function call_without_wip(fn)
  local was_disabled = disabled
  disabled = true

  local ok, result = pcall(fn)
  disabled = was_disabled

  if not ok then
    error(result)
  end

  return result
end

local function enabled(phase)
  if disabled then
    return false
  end

  local config = require("anvil.config").values.wip or {}
  return config.enabled == true and config[phase] ~= false
end

local function current_branch()
  local branch = git.cli.branch.current.call { hidden = true, trim = true, wip_skip = true }.stdout[1]
  if branch and branch ~= "" then
    return branch
  end

  branch = git.repo.state.head.branch
  if branch and branch ~= "" and branch ~= "(detached)" then
    return branch
  end
end

local function current_name()
  local branch = current_branch()
  if not branch then
    return "detached-" .. (git.repo.state.head.abbrev or "initial")
  end

  return branch:gsub("[^%w%._/-]", "-")
end

local function ref(kind)
  return ("refs/wip/%s/%s"):format(kind, current_name())
end

local function parent_args()
  if git.repo.state.head.oid then
    return { "-p", git.repo.state.head.oid }
  end

  return {}
end

local function subject()
  return ("WIP on %s: %s"):format(current_branch() or "(detached)", git.repo.state.head.abbrev or "initial")
end

local function update_ref(name, oid, message)
  git.cli["update-ref"].create_reflog.message(message).args(name, oid).call { await = true, wip_skip = true }
end

---@return string|nil
function M.snapshot_index()
  if not git.status.anything_staged() then
    return nil
  end

  local tree = git.cli["write-tree"].call { hidden = true, await = true, wip_skip = true }.stdout[1]
  if not tree or tree == "" then
    return nil
  end

  local commit = git.cli["commit-tree"]
    .arg_list(vim.list_extend(parent_args(), { "-m", subject(), tree }))
    .call { hidden = true, await = true, wip_skip = true }.stdout[1]

  if commit and commit ~= "" then
    update_ref(ref("index"), commit, "anvil wip index")
    return commit
  end
end

---@return string|nil
function M.snapshot_worktree()
  if not git.status.is_dirty() then
    return nil
  end

  local commit = git.cli.stash.args("create", subject()).call { hidden = true, await = true, wip_skip = true }.stdout[1]
  if commit and commit ~= "" then
    update_ref(ref("worktree"), commit, "anvil wip worktree")
    return commit
  end
end

function M.snapshot(opts)
  opts = opts or {}
  local index = M.snapshot_index()
  local worktree = M.snapshot_worktree()

  if opts.notify ~= false then
    if index or worktree then
      notification.info("WIP snapshot saved")
    else
      notification.info("No changes to snapshot")
    end
  end

  return { index = index, worktree = worktree }
end

function M.before_command(_command)
  if enabled("before") then
    return call_without_wip(function()
      return M.snapshot { notify = false }
    end)
  end
end

function M.after_command(_command)
  if enabled("after") then
    return call_without_wip(function()
      return M.snapshot { notify = false }
    end)
  end
end

function M.list()
  local result = git.cli["for-each-ref"]
    .sort("-committerdate")
    .format("%(refname)%00%(objectname:short)%00%(committerdate:relative)%00%(contents:subject)")
    .args("refs/wip")
    .call { hidden = true, wip_skip = true }

  local items = {}
  for _, line in ipairs(result.stdout) do
    if line ~= "" then
      local parts = vim.split(line, "\0", { plain = true })
      table.insert(items, {
        ref = parts[1],
        oid = parts[2],
        date = parts[3],
        message = parts[4],
        kind = parts[1] and (parts[1]:match("^refs/wip/([^/]+)/") or "wip") or "wip",
      })
    end
  end

  return items
end

---@param item table|string
---@return boolean, string|nil
function M.apply(item)
  local refname = type(item) == "table" and item.ref or item
  local kind = type(item) == "table" and item.kind or (refname and refname:match("^refs/wip/([^/]+)/"))
  if not refname or refname == "" then
    return false, "missing WIP ref"
  end

  local result
  if kind == "index" then
    local patch = git.cli.diff.args("--binary", refname .. "^", refname).call { hidden = true, await = true, wip_skip = true }
    if patch:failure() then
      return false, "failed to build WIP index patch"
    end

    local patch_file = vim.fn.tempname()
    vim.fn.writefile(patch.stdout, patch_file)
    result = git.cli.apply.args("--cached", patch_file).call { hidden = true, await = true, wip_skip = true }
    pcall(vim.fn.delete, patch_file)
  else
    result = git.cli.stash.args("apply", refname).call { hidden = true, await = true, wip_skip = true }
  end

  if result:failure() then
    return false, table.concat(result.stderr or {}, "\n")
  end

  notification.info("WIP snapshot applied")
  return true, nil
end

function M.register(meta)
  meta.update_wip = function(state)
    state.wip.items = M.list()
  end
end

return M
