![preview](https://github.com/NeogitOrg/neogit/assets/7228095/d964cbb4-a557-4e97-ac5b-ea571a001f5c)

## About this project

This project aims to be a complete, 1:1 rewrite of Emacs' [Magit](https://magit.vc) and
[Forge](https://github.com/magit/forge) for Neovim: the full git porcelain *and* the
GitHub/forge layer baked into a single plugin, sharing one status buffer, one section model,
and one popup system, exactly the way Forge extends Magit.

It stands on the shoulders of two excellent projects:

- **[Neogit](https://github.com/NeogitOrg/neogit)** - this repository is a fork of Neogit,
  which provides the Magit-style git porcelain this project builds on. All credit for the
  core architecture and the vast majority of the git functionality goes to the Anvil
  authors and contributors.
- **[octo.nvim](https://github.com/pwntester/octo.nvim)** - the inspiration and reference
  for the forge layer. Octo pioneered GitHub issue/PR editing inside Neovim via the `gh`
  CLI, and the forge subsystem here follows its approach (auth and GraphQL through `gh`,
  no credential handling in the plugin).

Where this fork goes beyond upstream Anvil today: a built-in **Forge** subsystem
(`N` popup, pull request/issue sections in the status buffer, local offline-first topic
store synced via `gh`), **git blame** (`:Anvil blame`, magit-blame style), and the
**run popup** (`!`) for arbitrary git/shell commands and WIP snapshots.

## Installation

Use whichever plugin manager suits your config. Anvil has no required Lua dependencies,
though the optional integrations below can make diffs, logs, and pickers nicer.

### `vim.pack`

Neovim 0.12+ ships a built-in plugin manager, `vim.pack`:

```lua
vim.pack.add({
  "https://github.com/memohnsen/anvil.nvim",

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
  "memohnsen/anvil.nvim",
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
  cmd = "Anvil",
  keys = {
    { "<leader>gg", "<cmd>Anvil<cr>", desc = "Show Anvil UI" }
  }
}
```

### `mini.deps`

```lua
local add = MiniDeps.add

add({
  source = "memohnsen/anvil.nvim",
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
  "memohnsen/anvil.nvim",
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

Anvil can also be installed with Neovim's built-in package support (`:help packages`),
with no plugin manager at all. Clone it (and any optional dependencies) into a package
directory on your `packpath`:

```sh
git clone https://github.com/memohnsen/anvil.nvim \
  ~/.config/nvim/pack/plugins/start/anvil.nvim
```

Then call `require("anvil").setup({})` somewhere in your config. Optional integrations
(diffview, codediff, baleia, telescope, fzf-lua, mini.pick, snacks) can be cloned into
the same `start` directory.

## Usage

You can either open Anvil by using the `Anvil` command:

```vim
:Anvil             " Open the status buffer in a new tab
:Anvil cwd=<cwd>   " Use a different repository path
:Anvil cwd=%:p:h   " Uses the repository of the current file
:Anvil kind=<kind> " Open specified popup directly
:Anvil commit      " Open commit popup
:Anvil forge       " Open forge popup (GitHub PRs/issues, requires `gh`)
:Anvil run         " Open run popup (arbitrary git/shell commands)
:Anvil blame       " Blame the current file (magit-blame style)
:Anvil patch       " Open patch/am popup
:Anvil notes       " Open git-notes popup
:Anvil submodule   " Open submodule popup
:Anvil clone       " Open clone popup
:Anvil file_dispatch " Open file-oriented dispatch popup
:Anvil sparse_checkout " Open sparse-checkout popup
:Anvil subtree     " Open subtree popup
:Anvil bundle      " Open bundle popup
:Anvil shortlog    " Open shortlog popup
:Anvil repos       " Open repositories list popup
:Anvil dispatch    " Open global dispatch popup
:Anvil mergetool   " Open mergetool popup

" Map it to a key
nnoremap <leader>gg <cmd>Anvil<cr>
```

```lua
-- Or via lua api
vim.keymap.set("n", "<leader>gg", "<cmd>Anvil<cr>", { desc = "Open Anvil UI" })
```

Or using the lua api:

```lua
local anvil = require('anvil')

-- open using defaults
anvil.open()

-- open a specific popup
anvil.open({ "commit" })

-- open the forge popup (fetch/browse/list/checkout GitHub PRs and issues)
anvil.open({ "forge" })

-- blame the current file
anvil.open({ "blame" })

-- open as a split
anvil.open({ kind = "split" })

-- open with different project
anvil.open({ cwd = "~" })

-- You can map this to a key
vim.keymap.set("n", "<leader>gg", anvil.open, { desc = "Open Anvil UI" })

-- Wrap in a function to pass additional arguments
vim.keymap.set(
    "n",
    "<leader>gg",
    function() anvil.open({ kind = "split" }) end,
    { desc = "Open Anvil UI" }
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

Configure Anvil by calling `require('anvil').setup {}` with a table of options.
Anvil works out of the box with no configuration.

```lua
require("anvil").setup {
  -- Use Treesitter to apply syntax highlighting to diff hunks
  treesitter_diff_highlight = true,
  -- Path to the git executable
  git_executable = "git",
  -- Watch the .git/ directory and auto-refresh the status buffer
  filewatcher = { enabled = true },
}
```

Every option — signs, integrations (diffview/codediff, telescope/fzf-lua/mini.pick/snacks),
mappings, sections, graph style, Forge, WIP, and more — is documented in the [wiki/](wiki) pages
and in `:help anvil`.

## Documentation

Detailed reference lives in the **[wiki/](wiki)** directory (and in `:help anvil` inside Neovim):

- **[Configuration](wiki/Configuration.md)** — every `setup {}` option and the full default config.
- **[Popups](wiki/Popups.md)** — the transient popup menus, argument state, and section navigation.
- **[Forge](wiki/Forge.md)** — the GitHub subsystem: sections, topic buffers, reviews, notifications.
- **[WIP Snapshots](wiki/WIP-Snapshots.md)** — Magit-style work-in-progress refs.
- **[Events](wiki/Events.md)** — the autocmd events Anvil emits.

Highlight groups are listed in `:help anvil`; if your theme doesn't style a particular group,
Anvil falls back to sensible defaults.

## Special Thanks

- [Neogit](https://github.com/NeogitOrg/neogit) and its contributors - this project is a fork of Neogit, which provides the entire git porcelain foundation
- [octo.nvim](https://github.com/pwntester/octo.nvim) - the inspiration and reference implementation for the forge/GitHub layer
- [Magit](https://magit.vc) and [Forge](https://github.com/magit/forge) - the gold standard this project is a 1:1 rewrite of
- [gitgraph.nvim](https://github.com/isakbm/gitgraph.nvim) for the "kitty" git graph renderer
- [vim-flog](https://github.com/rbong/vim-flog) for the "unicode" git graph renderer
