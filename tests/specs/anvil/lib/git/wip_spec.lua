local util = require("tests.util.util")
local git_repo = require("anvil.lib.git.repository")
local git = require("anvil.lib.git")
local config = require("anvil.config")

local function run(cmd)
  return util.system(cmd)
end

local function wait_for_refresh(repo)
  vim.wait(1000, function()
    return repo.state.head and repo.state.head.oid ~= nil
  end, 10)
end

local function in_repo(cb)
  return function()
    local root = util.create_temp_dir("wip")
    vim.api.nvim_set_current_dir(root)
    run { "git", "init" }
    run { "git", "config", "user.email", "test@anvil-test.test" }
    run { "git", "config", "user.name", "Anvil Test" }
    run { "sh", "-c", "printf 'one\\n' > file.txt" }
    run { "git", "add", "file.txt" }
    run { "git", "commit", "-m", "initial" }

    require("anvil").setup {}
    local repo = git_repo.instance(root)
    repo:dispatch_refresh()
    wait_for_refresh(repo)

    cb(root, repo)
  end
end

describe("git wip", function()
  local function ref_exists(ref)
    local result = vim.fn.systemlist({ "git", "rev-parse", "--verify", ref })
    return vim.v.shell_error == 0 and result[1] or nil
  end

  it(
    "saves dirty worktree state to a wip ref without cleaning the worktree",
    in_repo(function()
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      local branch = vim.trim(run { "git", "branch", "--show-current" })

      local commit = git.wip.snapshot_worktree()

      assert.is_not_nil(commit)
      assert.are.same(commit, vim.trim(run { "git", "rev-parse", "refs/wip/worktree/" .. branch }))
      assert.are.same(" M file.txt", (run { "git", "status", "--short" }):gsub("\n$", ""))
    end)
  )

  it(
    "saves staged state to a wip ref without unstaging it",
    in_repo(function()
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      run { "git", "add", "file.txt" }
      local branch = vim.trim(run { "git", "branch", "--show-current" })

      local commit = git.wip.snapshot_index()

      assert.is_not_nil(commit)
      assert.are.same(commit, vim.trim(run { "git", "rev-parse", "refs/wip/index/" .. branch }))
      assert.are.same("M  file.txt", (run { "git", "status", "--short" }):gsub("\n$", ""))
    end)
  )

  it(
    "does not write automatic wip refs by default",
    in_repo(function()
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      local branch = vim.trim(run { "git", "branch", "--show-current" })

      git.cli.reset.hard.call { await = true }

      assert.is_nil(ref_exists("refs/wip/worktree/" .. branch))
      assert.are.same("", (run { "git", "status", "--short" }):gsub("\n$", ""))
    end)
  )

  it(
    "writes automatic before-command wip refs for mutating anvil git operations when enabled",
    in_repo(function()
      config.values.wip.enabled = true
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      local branch = vim.trim(run { "git", "branch", "--show-current" })

      git.cli.reset.hard.call { await = true }

      assert.is_not_nil(ref_exists("refs/wip/worktree/" .. branch))
      assert.are.same("", (run { "git", "status", "--short" }):gsub("\n$", ""))
    end)
  )

  it(
    "applies dirty worktree WIP snapshots",
    in_repo(function()
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      local commit = git.wip.snapshot_worktree()

      run { "git", "reset", "--hard", "HEAD" }
      assert.are.same("one", (run { "cat", "file.txt" }):gsub("\n$", ""))

      local ok, err = git.wip.apply({ ref = commit, kind = "worktree" })

      assert.True(ok, err)
      assert.are.same("one\ntwo", (run { "cat", "file.txt" }):gsub("\n$", ""))
    end)
  )

  it(
    "applies staged index WIP snapshots",
    in_repo(function()
      run { "sh", "-c", "printf 'two\\n' >> file.txt" }
      run { "git", "add", "file.txt" }
      local commit = git.wip.snapshot_index()

      run { "git", "reset", "--hard", "HEAD" }
      assert.are.same("", (run { "git", "diff", "--cached", "--name-only" }):gsub("\n$", ""))

      local ok, err = git.wip.apply({ ref = commit, kind = "index" })

      assert.True(ok, err)
      assert.are.same("file.txt", (run { "git", "diff", "--cached", "--name-only" }):gsub("\n$", ""))
    end)
  )
end)
