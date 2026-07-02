> Detailed popup reference. See the [README](../README.md) for install and basics.

# Popups

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

Inside a log buffer, pressing the Log popup key (`l`) re-opens the popup scoped to that buffer, so
adjusting arguments re-runs the log in place instead of opening a new split (magit's
`magit-log-refresh`).

Popup arguments keep Magit-style transient state when `remember_settings` is enabled. Use
`<C-x>s` inside a popup to save the current arguments as defaults, `<C-x>p` to cycle previous
argument histories, `<C-x>r` to reset saved defaults for that popup, and `<C-x>l` to cycle the
transient display level (1/4/7), hiding argument suffixes tagged above the current level
(magit's transient levels; suffixes default to level 1). Any popup action can read the numeric
prefix argument typed before its key (Neovim's count, the analog of magit's `C-u`) via
`popup:get_prefix()` / `popup:has_prefix()`.

The submodule popup (`O`) includes a list buffer via `L`; from that buffer, use `u` update,
`s` sync, or `d` deinit on the selected submodule.

Status buffers include Magit-style section navigation aliases: `n`/`p` move to next/previous
section, `^` jumps to the current section header, `J` opens a picker to jump to any section,
and `M-1`..`M-4` mirror the existing section depth controls.
