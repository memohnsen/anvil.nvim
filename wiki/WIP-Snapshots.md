> WIP snapshot reference. See the [README](../README.md) for install and basics.

# WIP snapshots

The run popup also includes Magit-style WIP snapshot commands:

- `! w` saves the current dirty worktree to `refs/wip/worktree/<branch>`.
- `! W` saves the staged index to `refs/wip/index/<branch>`.
- `! l` opens a WIP snapshot list; press `<cr>` or `a` to apply the selected snapshot.

Snapshots are ordinary git refs with reflogs, so they do not clean or stash your working tree.
When present, they appear in the status buffer under `WIP snapshots`.

Automatic WIP snapshots are opt-in:

```lua
require("anvil").setup({
  wip = {
    enabled = true,
    before = true,
    after = false,
  },
})
```

When enabled, Anvil writes WIP refs around mutating git operations it runs. `before`
captures your state before the operation starts, and `after` can additionally capture
the successful result.
