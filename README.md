![preview](https://github.com/NeogitOrg/neogit/assets/7228095/d964cbb4-a557-4e97-ac5b-ea571a001f5c)

## About this project

This project aims to be a complete, 1:1 rewrite of Emacs' [Magit](https://magit.vc) and
[Forge](https://github.com/magit/forge) for Neovim: the full git porcelain *and* the
GitHub/forge layer baked into a single plugin, sharing one status buffer, one section model,
and one popup system, exactly the way Forge extends Magit.

It stands on the shoulders of two excellent projects:

- **[Neogit](https://github.com/NeogitOrg/neogit)** - this repository is a fork of Neogit,
  which provides the Magit-style git porcelain this project builds on. All credit for the
  core architecture and the vast majority of the git functionality goes to the Neogit
  authors and contributors.
- **[octo.nvim](https://github.com/pwntester/octo.nvim)** - the inspiration and reference
  for the forge layer. Octo pioneered GitHub issue/PR editing inside Neovim via the `gh`
  CLI, and the forge subsystem here follows its approach (auth and GraphQL through `gh`,
  no credential handling in the plugin).

Where this fork goes beyond upstream Neogit today: a built-in **Forge** subsystem
(`N` popup, pull request/issue sections in the status buffer, local offline-first topic
store synced via `gh`), **git blame** (`:Neogit blame`, magit-blame style), and the
**run popup** (`!`) for arbitrary git/shell commands and WIP snapshots. See [PLAN.md](PLAN.md) for the full
parity roadmap (topic view buffers, PR reviews, notifications, submodules, patches, and
more are in progress).

AI Disclosure: Any and all changes to the base neogit repo have been done by Claude Fable and ChatGPT.

## Installation

Use whichever plugin manager suits your config. Neogit has no required Lua dependencies,
though the optional integrations below can make diffs, logs, and pickers nicer.

### `vim.pack`

Neovim 0.12+ ships a built-in plugin manager, `vim.pack`:

```lua
vim.pack.add({
  "https://github.com/NeogitOrg/neogit",

  -- Optional integrations; keep whichever ones you use.
  "https://github.com/sindrets/diffview.nvim",
  "https://github.com/esmuellert/codediff.nvim",
  "https://github.com/m00qek/baleia.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
  "https://github.com/ibhagwan/fzf-lua",
  "https://github.com/nvim-mini/mini.pick",
  "https://github.com/folke/snacks.nvim",
  "https://github.com/kkharji/sqlite.lua", -- optional Forge store backend
})
```

### `lazy.nvim`

```lua
{
  "NeogitOrg/neogit",
  lazy = true,
  dependencies = {
    -- Only one of these is needed.
    "sindrets/diffview.nvim",        -- optional
    "esmuellert/codediff.nvim",      -- optional

    -- For a custom log pager
    "m00qek/baleia.nvim",            -- optional

    -- Only one of these is needed.
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua",              -- optional
    "nvim-mini/mini.pick",           -- optional
    "folke/snacks.nvim",             -- optional

    "kkharji/sqlite.lua",            -- optional Forge store backend
  },
  cmd = "Neogit",
  keys = {
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" }
  }
}
```

### `mini.deps`

```lua
local add = MiniDeps.add

add({
  source = "NeogitOrg/neogit",
  depends = {
    -- Optional integrations; keep whichever ones you use.
    "sindrets/diffview.nvim",
    "esmuellert/codediff.nvim",
    "m00qek/baleia.nvim",
    "nvim-telescope/telescope.nvim",
    "ibhagwan/fzf-lua",
    "nvim-mini/mini.pick",
    "folke/snacks.nvim",
  },
})
```

### `packer.nvim`

```lua
use({
  "NeogitOrg/neogit",
  requires = {
    -- Optional integrations; keep whichever ones you use.
    "sindrets/diffview.nvim",
    "esmuellert/codediff.nvim",
    "m00qek/baleia.nvim",
    "nvim-telescope/telescope.nvim",
    "ibhagwan/fzf-lua",
    "nvim-mini/mini.pick",
    "folke/snacks.nvim",
  },
})
```

### Vim packages

If you manage packages directly, clone Neogit into a `start` package:

```sh
git clone https://github.com/NeogitOrg/neogit \
  "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/neogit/start/neogit
```

## Usage

You can either open Neogit by using the `Neogit` command:

```vim
:Neogit             " Open the status buffer in a new tab
:Neogit cwd=<cwd>   " Use a different repository path
:Neogit cwd=%:p:h   " Uses the repository of the current file
:Neogit kind=<kind> " Open specified popup directly
:Neogit commit      " Open commit popup
:Neogit forge       " Open forge popup (GitHub PRs/issues, requires `gh`)
:Neogit run         " Open run popup (arbitrary git/shell commands)
:Neogit blame       " Blame the current file (magit-blame style)
:Neogit patch       " Open patch/am popup
:Neogit notes       " Open git-notes popup
:Neogit submodule   " Open submodule popup
:Neogit clone       " Open clone popup
:Neogit file_dispatch " Open file-oriented dispatch popup
:Neogit sparse_checkout " Open sparse-checkout popup
:Neogit subtree     " Open subtree popup
:Neogit bundle      " Open bundle popup
:Neogit shortlog    " Open shortlog popup
:Neogit repos       " Open repositories list popup
:Neogit dispatch    " Open global dispatch popup
:Neogit mergetool   " Open mergetool popup

" Map it to a key
nnoremap <leader>gg <cmd>Neogit<cr>
```

```lua
-- Or via lua api
vim.keymap.set("n", "<leader>gg", "<cmd>Neogit<cr>", { desc = "Open Neogit UI" })
```

Or using the lua api:

```lua
local neogit = require('neogit')

-- open using defaults
neogit.open()

-- open a specific popup
neogit.open({ "commit" })

-- open the forge popup (fetch/browse/list/checkout GitHub PRs and issues)
neogit.open({ "forge" })

-- blame the current file
neogit.open({ "blame" })

-- open as a split
neogit.open({ kind = "split" })

-- open with different project
neogit.open({ cwd = "~" })

-- You can map this to a key
vim.keymap.set("n", "<leader>gg", neogit.open, { desc = "Open Neogit UI" })

-- Wrap in a function to pass additional arguments
vim.keymap.set(
    "n",
    "<leader>gg",
    function() neogit.open({ kind = "split" }) end,
    { desc = "Open Neogit UI" }
)
```

The `kind` option can be one of the following values:
- `tab`      (default)
- `replace`
- `split`
- `split_above`
- `split_above_all`
- `split_below`
- `split_below_all`
- `vsplit`
- `floating`
- `auto` (`vsplit` if window would have 80 cols, otherwise `split`)

## Configuration

You can configure neogit by running the `require('neogit').setup {}` function, passing a table as the argument.

<details>
<summary>Default Config</summary>

```lua
local neogit = require("neogit")

neogit.setup {
  -- Use Treesitter to apply syntax highlighting to diff hunks
  treesitter_diff_highlight = true,
  -- Apply word-diff highlights to diff hunks
  word_diff_highlight = true,
  -- Hides the hints at the top of the status buffer
  disable_hint = false,
  -- Disables changing the buffer highlights based on where the cursor is.
  disable_context_highlighting = false,
  -- Disables signs for sections/items/hunks
  disable_signs = false,
  -- Path to git executable. Defaults to "git". Can be used to specify a custom git binary or wrapper script.
  git_executable = "git",
  -- Offer to force push when branches diverge
  prompt_force_push = true,
  -- Request confirmation when amending already published commits
  prompt_amend_commit = true,
  -- Changes what mode the Commit Editor starts in. `true` will leave nvim in normal mode, `false` will change nvim to
  -- insert mode, and `"auto"` will change nvim to insert mode IF the commit message is empty, otherwise leaving it in
  -- normal mode.
  disable_insert_on_commit = "auto",
  -- When enabled, will watch the `.git/` directory for changes and refresh the status buffer in response to filesystem
  -- events.
  filewatcher = {
    interval = 1000,
    enabled = true,
  },
  -- "ascii"   is the graph the git CLI generates
  -- "unicode" is the graph like https://github.com/rbong/vim-flog
  -- "kitty"   is the graph like https://github.com/isakbm/gitgraph.nvim - use https://github.com/rbong/flog-symbols if you don't use Kitty
  graph_style = "ascii",
  -- Show relative date by default. When set, use `strftime` to display dates
  commit_date_format = nil,
  log_date_format = nil,
  -- When set, used to format the diff. Requires *baleia* to colorize text with ANSI escape sequences. An example for `Delta` is `{ 'delta', '--width', '117' }`. For `Delta`, hyperlinks must be disabled when called by `neogit`, for text to be colorized properly.
  log_pager = nil,
  -- Show message with spinning animation when a git command is running.
  process_spinner = false,
  -- Used to generate URL's for branch popup action "pull request", "open commit" and "open tree"
  git_services = {
    ["github.com"] = {
      pull_request = "https://github.com/${owner}/${repository}/compare/${branch_name}?expand=1",
      commit = "https://github.com/${owner}/${repository}/commit/${oid}",
      tree = "https://${host}/${owner}/${repository}/tree/${branch_name}",
    },
    ["bitbucket.org"] = {
      pull_request = "https://bitbucket.org/${owner}/${repository}/pull-requests/new?source=${branch_name}&t=1",
      commit = "https://bitbucket.org/${owner}/${repository}/commits/${oid}",
      tree = "https://bitbucket.org/${owner}/${repository}/branch/${branch_name}",
    },
    ["gitlab.com"] = {
      pull_request = "https://gitlab.com/${owner}/${repository}/merge_requests/new?merge_request[source_branch]=${branch_name}",
      commit = "https://gitlab.com/${owner}/${repository}/-/commit/${oid}",
      tree = "https://gitlab.com/${owner}/${repository}/-/tree/${branch_name}?ref_type=heads",
    },
    ["azure.com"] = {
      pull_request = "https://dev.azure.com/${owner}/_git/${repository}/pullrequestcreate?sourceRef=${branch_name}&targetRef=${target}",
      commit = "",
      tree = "",
    },
    ["codeberg.org"] = {
      pull_request = "https://${host}/${owner}/${repository}/compare/${branch_name}",
      commit = "https://${host}/${owner}/${repository}/commit/${oid}",
      tree = "https://${host}/${owner}/${repository}/src/branch/${branch_name}",
    },
  },
  -- Allows a different telescope sorter. Defaults to 'fuzzy_with_index_bias'. The example below will use the native fzf
  -- sorter instead. By default, this function returns `nil`.
  telescope_sorter = function()
    return require("telescope").extensions.fzf.native_fzf_sorter()
  end,
  -- Persist the values of switches/options within and across sessions
  remember_settings = true,
  -- Scope persisted settings on a per-project basis
  use_per_project_settings = true,
  -- Table of settings to never persist. Uses format "Filetype--cli-value"
  ignored_settings = {},
  -- Configure highlight group features
  highlight = {
    italic = true,
    bold = true,
    underline = true
  },
  -- Set to false if you want to be responsible for creating _ALL_ keymappings
  use_default_keymaps = true,
  -- Neogit refreshes its internal state after specific events, which can be expensive depending on the repository size.
  -- Disabling `auto_refresh` will make it so you have to manually refresh the status after you open it.
  auto_refresh = true,
  -- Value used for `--sort` option for `git branch` command
  -- By default, branches will be sorted by commit date descending
  -- Flag description: https://git-scm.com/docs/git-branch#Documentation/git-branch.txt---sortltkeygt
  -- Sorting keys: https://git-scm.com/docs/git-for-each-ref#_options
  sort_branches = "-committerdate",
  -- Value passed to the `--<commit_order>-order` flag of the `git log` command
  -- Determines how commits are traversed and displayed in the log / graph:
  --   "topo"         topological order (parents always before children, good for graphs, slower on large repos)
  --   "date"         chronological order by commit date
  --   "author-date"  chronological order by author date
  --   ""             disable explicit ordering (fastest, recommended for very large repos)
  commit_order = "topo",
  -- Default for new branch name prompts
  initial_branch_name = "",
  -- Default for rename branch prompt. If not set, the current branch name is used
  initial_branch_rename = nil,
  -- Change the default way of opening neogit
  kind = "tab",
  -- Floating window style 
  floating = {
    relative = "editor",
    width = 0.8,
    height = 0.7,
    style = "minimal",
    border = "rounded",
  },
  -- Disable line numbers
  disable_line_numbers = true,
  -- Disable relative line numbers
  disable_relative_line_numbers = true,
  -- The time after which an output console is shown for slow running commands
  console_timeout = 2000,
  -- Automatically show console if a command takes more than console_timeout milliseconds
  auto_show_console = true,
  -- Automatically close the console if the process exits with a 0 (success) status
  auto_close_console = true,
  notification_icon = "󰊢",
  status = {
    show_head_commit_hash = true,
    recent_commit_count = 10,
    HEAD_padding = 10,
    HEAD_folded = false,
    mode_padding = 3,
    mode_text = {
      M = "modified",
      N = "new file",
      A = "added",
      D = "deleted",
      C = "copied",
      U = "updated",
      R = "renamed",
      T = "changed",
      DD = "unmerged",
      AU = "unmerged",
      UD = "unmerged",
      UA = "unmerged",
      DU = "unmerged",
      AA = "unmerged",
      UU = "unmerged",
      ["?"] = "",
    },
  },
  commit_editor = {
    kind = "tab",
    show_staged_diff = true,
    -- Accepted values:
    -- "split" to show the staged diff below the commit editor
    -- "vsplit" to show it to the right
    -- "split_above" Like :top split
    -- "vsplit_left" like :vsplit, but open to the left
    -- "auto" "vsplit" if window would have 80 cols, otherwise "split"
    staged_diff_split_kind = "split",
    spell_check = true,
  },
  commit_select_view = {
    kind = "tab",
  },
  commit_view = {
    kind = "vsplit",
    verify_commit = vim.fn.executable("gpg") == 1, -- Can be set to true or false, otherwise we try to find the binary
  },
  log_view = {
    kind = "tab",
  },
  rebase_editor = {
    kind = "auto",
  },
  reflog_view = {
    kind = "tab",
  },
  merge_editor = {
    kind = "auto",
  },
  preview_buffer = {
    kind = "floating_console",
  },
  popup = {
    kind = "split",
    show_title = false,
  },
  stash = {
    kind = "tab",
  },
  refs_view = {
    kind = "tab",
  },
  signs = {
    -- { CLOSED, OPENED }
    hunk = { "", "" },
    item = { ">", "v" },
    section = { ">", "v" },
  },
  -- Each Integration is auto-detected through plugin presence, however, it can be disabled by setting to `false`
  integrations = {
    -- If enabled, use telescope for menu selection rather than vim.ui.select.
    -- Allows multi-select and some things that vim.ui.select doesn't.
    telescope = nil,
    -- Neogit only provides inline diffs. If you want a more traditional way to look at diffs, you can use `diffview`.
    -- The diffview integration enables the diff popup.
    --
    -- Requires you to have `sindrets/diffview.nvim` installed.
    diffview = nil,

    -- Alternative diff viewer integration.
    -- Requires you to have `esmuellert/codediff.nvim` installed.
    codediff = nil,

    -- If enabled, uses fzf-lua for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `ibhagwan/fzf-lua` installed.
    fzf_lua = nil,

    -- If enabled, uses mini.pick for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `echasnovski/mini.pick` installed.
    mini_pick = nil,

    -- If enabled, uses snacks.picker for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `folke/snacks.nvim` installed.
    snacks = nil,
  },
  -- Which diff viewer to use. nil = auto-detect (tries diffview first, then codediff).
  -- Can be "diffview" or "codediff".
  diff_viewer = nil,
  sections = {
    -- Reverting/Cherry Picking
    sequencer = {
      folded = false,
      hidden = false,
    },
    untracked = {
      folded = false,
      hidden = false,
    },
    unstaged = {
      folded = false,
      hidden = false,
    },
    staged = {
      folded = false,
      hidden = false,
    },
    stashes = {
      folded = true,
      hidden = false,
    },
    unpulled_upstream = {
      folded = true,
      hidden = false,
    },
    unmerged_upstream = {
      folded = false,
      hidden = false,
    },
    unpulled_pushRemote = {
      folded = true,
      hidden = false,
    },
    unmerged_pushRemote = {
      folded = false,
      hidden = false,
    },
    recent = {
      folded = true,
      hidden = false,
    },
    rebase = {
      folded = true,
      hidden = false,
    },
    -- Forge: open pull requests for the current GitHub repository.
    -- Populated from the local store; sync with the forge popup ("N f").
    pullreqs = {
      folded = true,
      hidden = false,
    },
    -- Forge: open issues for the current GitHub repository.
    issues = {
      folded = true,
      hidden = false,
    },
  },
  mappings = {
    commit_editor = {
      ["q"] = "Close",
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
      ["<m-p>"] = "PrevMessage",
      ["<m-n>"] = "NextMessage",
      ["<m-r>"] = "ResetMessage",
    },
    commit_editor_I = {
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
    },
    rebase_editor = {
      ["p"] = "Pick",
      ["r"] = "Reword",
      ["e"] = "Edit",
      ["s"] = "Squash",
      ["f"] = "Fixup",
      ["x"] = "Execute",
      ["d"] = "Drop",
      ["b"] = "Break",
      ["q"] = "Close",
      ["<cr>"] = "OpenCommit",
      ["gk"] = "MoveUp",
      ["gj"] = "MoveDown",
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
      ["[c"] = "OpenOrScrollUp",
      ["]c"] = "OpenOrScrollDown",
    },
    rebase_editor_I = {
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
    },
    finder = {
      ["<cr>"] = "Select",
      ["<c-c>"] = "Close",
      ["<esc>"] = "Close",
      ["<c-n>"] = "Next",
      ["<c-p>"] = "Previous",
      ["<down>"] = "Next",
      ["<up>"] = "Previous",
      ["<tab>"] = "InsertCompletion",
      ["<c-y>"] = "CopySelection",
      ["<space>"] = "MultiselectToggleNext",
      ["<s-space>"] = "MultiselectTogglePrevious",
      ["<c-j>"] = "NOP",
      ["<ScrollWheelDown>"] = "ScrollWheelDown",
      ["<ScrollWheelUp>"] = "ScrollWheelUp",
      ["<ScrollWheelLeft>"] = "NOP",
      ["<ScrollWheelRight>"] = "NOP",
      ["<LeftMouse>"] = "MouseClick",
      ["<2-LeftMouse>"] = "NOP",
    },
    -- Setting any of these to `false` will disable the mapping.
    popup = {
      ["?"] = "HelpPopup",
      ["A"] = "CherryPickPopup",
      ["d"] = "DiffPopup",
      ["M"] = "RemotePopup",
      ["P"] = "PushPopup",
      ["X"] = "ResetPopup",
      ["Z"] = "WorktreePopup",
      ["z"] = "StashPopup",
      ["i"] = "IgnorePopup",
      ["t"] = "TagPopup",
      ["b"] = "BranchPopup",
      ["B"] = "BisectPopup",
      ["c"] = "CommitPopup",
      ["f"] = "FetchPopup",
      ["l"] = "LogPopup",
      ["m"] = "MergePopup",
      ["p"] = "PullPopup",
      ["r"] = "RebasePopup",
      ["v"] = "RevertPopup",
      ["!"] = "RunPopup",
      ["N"] = "ForgePopup",
      ["W"] = "PatchPopup",
      ["T"] = "NotesPopup",
      ["O"] = "SubmodulePopup",
      ["C"] = "ClonePopup",
      ["h"] = "DispatchPopup",
      ["e"] = "MergetoolPopup",
    },
    status = {
      ["j"] = "MoveDown",
      ["k"] = "MoveUp",
      ["o"] = "OpenTree",
      ["q"] = "Close",
      ["I"] = "InitRepo",
      ["1"] = "Depth1",
      ["2"] = "Depth2",
      ["3"] = "Depth3",
      ["4"] = "Depth4",
      ["Q"] = "Command",
      ["<tab>"] = "Toggle",
      ["za"] = "Toggle",
      ["zo"] = "OpenFold",
      ["x"] = "Discard",
      ["s"] = "Stage",
      ["S"] = "StageUnstaged",
      ["<c-s>"] = "StageAll",
      ["u"] = "Unstage",
      ["K"] = "Untrack",
      ["U"] = "UnstageStaged",
      ["y"] = "ShowRefs",
      ["$"] = "CommandHistory",
      ["Y"] = "YankSelected",
      ["gp"] = "GoToParentRepo",
      ["<c-r>"] = "RefreshBuffer",
      ["<cr>"] = "GoToFile",
      ["<s-cr>"] = "PeekFile",
      ["<c-v>"] = "VSplitOpen",
      ["<c-x>"] = "SplitOpen",
      ["<c-t>"] = "TabOpen",
      ["{"] = "GoToPreviousHunkHeader",
      ["}"] = "GoToNextHunkHeader",
      ["[c"] = "OpenOrScrollUp",
      ["]c"] = "OpenOrScrollDown",
      ["<c-k>"] = "PeekUp",
      ["<c-j>"] = "PeekDown",
      ["<c-n>"] = "NextSection",
      ["<c-p>"] = "PreviousSection",
    },
  },
}
```
</details>


## Popups

The following popup menus are available from all buffers:
- Bisect
- Branch + Branch Config
- Bundle
- Cherry Pick
- Commit
- Diff
- Dispatch (`h`)
- Fetch
- File Dispatch
- Forge (GitHub pull requests + issues, `N`)
- Ignore
- Log
- Mergetool (`e`)
- Merge
- Notes (`T`)
- Patch/Am (`W`)
- Pull
- Push
- Rebase
- Remote + Remote Config
- Repositories
- Reset
- Revert
- Run (arbitrary git/shell commands, `!`)
- Shortlog
- Sparse Checkout
- Stash
- Submodule (`O`)
- Subtree
- Tag
- Worktree

Many popups will use whatever is currently under the cursor or selected as input for an action. For example, to cherry-pick a range of commits from the log view, a linewise visual selection can be made, and using either `apply` or `pick` from the cherry-pick menu will use the selection.

This works for just about everything that has an object-ID in git, and if you find one that you think _should_ work but doesn't, open an issue :)

Popup arguments keep Magit-style transient state when `remember_settings` is enabled. Use
`<C-x>s` inside a popup to save the current arguments as defaults, `<C-x>p` to cycle previous
argument histories, and `<C-x>r` to reset saved defaults for that popup.

The submodule popup (`O`) includes a list buffer via `L`; from that buffer, use `u` update,
`s` sync, or `d` deinit on the selected submodule.

Status buffers include Magit-style section navigation aliases: `n`/`p` move to next/previous
section, `^` jumps to the current section header, and `M-1`..`M-4` mirror the existing
section depth controls.

## Forge

The forge subsystem integrates GitHub into the status buffer and popup system, the same way
[Forge](https://github.com/magit/forge) integrates with Magit. It is inspired by (and
follows the architecture of) [octo.nvim](https://github.com/pwntester/octo.nvim).

**Requirements:** the [GitHub CLI](https://cli.github.com/) (`gh`) installed and
authenticated (`gh auth login`), and a GitHub remote named `origin` or `upstream`.
Everything degrades gracefully when these aren't present: no sections render and
popup actions explain what's missing.

**How it works:** topics are kept in a local store (`stdpath("data")/neogit/forge/`),
so the status buffer renders instantly and offline; the network is only touched when
you sync. If `kkharji/sqlite.lua` is installed, Neogit uses SQLite; otherwise it
falls back to the JSON store. This mirrors Forge's local-database design.

Open the forge popup with `N` from any Neogit buffer (or `:Neogit forge`):

| Key   | Action                                                      |
|-------|-------------------------------------------------------------|
| `f f` | Pull open PRs, issues, and discussions into the local store  |
| `c i` | Create issue (opens browser)                                |
| `c p` | Create pull request (`gh pr create --web`)                  |
| `b I` | Browse issues on the web                                    |
| `b P` | Browse pull requests on the web                             |
| `b r` | Browse repository on the web                                |
| `b b` | Browse current branch on the web                            |
| `l t` | List topics (picker), open selection in browser             |
| `l d` | List discussions in a Neogit buffer                         |
| `l n` | List notifications in a Neogit buffer                       |
| `b f` | Checkout a pull request branch (`gh pr checkout`)           |

After a sync, **Pull requests** and **Issues** sections appear in the status buffer
(configurable via `sections.pullreqs` / `sections.issues`). **Discussions** are synced
too, but `sections.discussions.hidden` defaults to `true`, matching Forge's optional
discussion sections. Rows carry the topic URL, so `Y` yanks it.

Topic view buffers render stored descriptions, comments, and PR reviews. Press `f` in a
topic buffer to pull fresh detail for that issue or pull request. Issue and pull request
topic buffers also support `c` comment with a multi-line post editor, `e` edit title,
`b` edit body in a multi-line editor, `l` add labels,
`a` add assignees, `m` set milestone, `+` add a reaction, and `s` toggle open/closed state through `gh`;
pull request topic buffers additionally support `r` add reviewers, `R` remove reviewers,
`V` queue a pending review comment, `A` approve, `v` submit a comment review, and `X`
request changes; successful edits refresh the local topic detail.
Local Forge topic marks are available with `M` mark read, `u` mark unread, `*` save/unsave,
and `d` mark done; list and status buffers show `U`/`S`/`D` markers.
Topic list buffers default to active topics; use `A` all, `U` unread, `S` saved, `D` done,
`O` open, `C` closed, `a` author, `r` assignee, `l` label, and `m` milestone filters.
Pull request topic detail also renders inline review threads with file/line context, diff hunks,
resolution state, and comments. Use `i` to reply to a numbered review thread, `x` to resolve it,
and `U` to mark it unresolved. Comment and reply editors submit on write or the commit-editor
submit mapping. Use `C` to react to a numbered topic comment and `I` to react to a numbered
review-thread comment. Suggested changes in review comments are listed in the topic buffer; use
`S` to apply a numbered suggestion to the local worktree.

Notification buffers support `r` mark read, `u` mark unread, `s` save/unsave, `d` mark
done, `g` refresh, `A`/`U`/`S`/`D` filter all/unread/saved/done, and `o` open the
notification target. Read/unread/save/done state is stored locally;
mark-read also updates GitHub when `gh` is available and authenticated.
See [PLAN.md](PLAN.md).

Notification polling is opt-in:

```lua
require("neogit").setup({
  forge = {
    notifications = {
      poll = true,
      interval = 300000,
    },
  },
})
```

By default notifications update only when you press `N f n` or `g` inside the notification buffer.

## WIP snapshots

The run popup also includes Magit-style WIP snapshot commands:

- `! w` saves the current dirty worktree to `refs/wip/worktree/<branch>`.
- `! W` saves the staged index to `refs/wip/index/<branch>`.
- `! l` opens a WIP snapshot list; press `<cr>` or `a` to apply the selected snapshot.

Snapshots are ordinary git refs with reflogs, so they do not clean or stash your working tree.
When present, they appear in the status buffer under `WIP snapshots`.

Automatic WIP snapshots are opt-in:

```lua
require("neogit").setup({
  wip = {
    enabled = true,
    before = true,
    after = false,
  },
})
```

When enabled, Neogit writes WIP refs around mutating git operations it runs. `before`
captures your state before the operation starts, and `after` can additionally capture
the successful result.

## Highlight Groups

See the built-in documentation for a comprehensive list of highlight groups. If your theme doesn't style a particular group, we'll try our best to do a nice job.


## Events

Neogit emits the following events:

| Event                   | Description                              | Event Data                                      |
|-------------------------|------------------------------------------|-------------------------------------------------|
| `NeogitStatusRefreshed` | Status has been reloaded                 | `{}`                                            |
| `NeogitCommitComplete`  | Commit has been created                  | `{}`                                            |
| `NeogitPushComplete`    | Push has completed                       | `{}`                                            |
| `NeogitPullComplete`    | Pull has completed                       | `{}`                                            |
| `NeogitFetchComplete`   | Fetch has completed                      | `{}`                                            |
| `NeogitBranchCreate`    | Branch was created, starting from `base` | `{ branch_name: string, base: string? }`        |
| `NeogitBranchDelete`    | Branch was deleted                       | `{ branch_name: string }`                       |
| `NeogitBranchCheckout`  | Branch was checked out                   | `{ branch_name: string }`                       |
| `NeogitBranchReset`     | Branch was reset to a commit/branch      | `{ branch_name: string, resetting_to: string }` |
| `NeogitBranchRename`    | Branch was renamed                       | `{ branch_name: string, new_name: string }`     |
| `NeogitRebase`        | A rebase finished                        | `{ commit: string, status: "ok"\|"conflict" }`    |
| `NeogitReset`         | A branch was reset to a certain commit   | `{ commit: string, mode: "soft"\|"mixed"\|"hard"\|"keep"\|"index" }` |
| `NeogitTagCreate`     | A tag was placed on a certain commit     | `{ name: string, ref: string }`                   |
| `NeogitTagDelete`     | A tag was removed                        | `{ name: string }`                                |
| `NeogitCherryPick`    | One or more commits were cherry-picked    | `{ commits: string[] }`                          |
| `NeogitMerge`         | A merge finished                          | `{ branch: string, args = string[], status: "ok"\|"conflict" }` |
| `NeogitStash`         | A stash finished                          | `{ success: boolean }` |
| `NeogitForgePulled`   | Forge topics were synced from GitHub      | `{}` |
| `NeogitForgePullRequestCheckout` | A PR branch was checked out via the forge popup | `{ number: number }` |
| `NeogitUserCommandComplete` | A command from the run popup finished | `{ cmd: string, cwd: string }` |

## Versioning

Neogit follows semantic versioning.

## Compatibility

The `master` branch will always be compatible with the latest **stable** release of Neovim, and usually with the latest **nightly** build as well.

## Contributing

See [CONTRIBUTING.md](https://github.com/NeogitOrg/neogit/blob/master/CONTRIBUTING.md) for more details.

## Special Thanks

- [Neogit](https://github.com/NeogitOrg/neogit) and its contributors - this project is a fork of Neogit, which provides the entire git porcelain foundation
- [octo.nvim](https://github.com/pwntester/octo.nvim) - the inspiration and reference implementation for the forge/GitHub layer
- [Magit](https://magit.vc) and [Forge](https://github.com/magit/forge) - the gold standard this project is a 1:1 rewrite of
- [gitgraph.nvim](https://github.com/isakbm/gitgraph.nvim) for the "kitty" git graph renderer
- [vim-flog](https://github.com/rbong/vim-flog) for the "unicode" git graph renderer
