# blame_view integration notes

This subsystem is self-contained (no existing files were modified). To wire it
into anvil, the following is needed:

## Entry point

Add a `blame` sub-command to the `:Anvil` command dispatcher so users can run
it from a file buffer:

```lua
-- e.g. in lua/anvil.lua / the command dispatcher:
blame = function()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    require("anvil.lib.notification").error("Buffer is not backed by a file")
    return
  end

  require("anvil.buffers.blame_view").new(file):open()
end
```

Suggested user-facing binding (documentation only, not set by this code):
`:Anvil blame`, or a popup entry in the future.

## Public API

```lua
local BlameView = require("anvil.buffers.blame_view")

BlameView.new(file_path, rev) -- file_path: absolute or worktree-relative; rev: optional revision
  :open(kind)                 -- kind defaults to "replace" (blame in place, like magit)
BlameView.is_open()           -- boolean
BlameView.instance            -- currently open instance, or nil

require("anvil.lib.git").blame.run(file, rev) -- data layer; returns BlameHunk[]|nil, err
```

## Config keys assumed / deferred

- No new keys were added to `config.lua` (constraint: no existing-file edits).
  If desired, add:

  ```lua
  blame_view = {
    kind = "replace", -- passed to BlameView:open(kind)
  },
  ```

  and open with `:open(config.values.blame_view.kind)`.

- Keymaps are currently hardcoded in the blame buffer (`<cr>`, `b`, `B`, `n`,
  `p`, `<esc>`) plus the user-configured `status` mappings for `Close` and
  `YankSelected`. To make them fully configurable, add a
  `mappings.blame_view` table to config.lua and a
  `get_reversed_blame_view_maps()` helper, mirroring
  `get_reversed_commit_view_maps()`.

## Behavior notes

- Buffer kind is `"replace"`: the blame view takes over the current window
  (magit-style) and `q`/`<esc>` restores the original buffer and a cursor
  position corresponding to the blame line under the cursor.
- Uncommitted lines (all-zero sha) render as "Uncommitted changes"; `<cr>` on
  them is a no-op with a notice, `b` reblames at `HEAD`.
- `b`/`B` (blame from blame) uses the porcelain `previous` header (sha +
  filename, rename-aware) when available, falling back to `<sha>^`.
- File content is rendered without syntax highlighting: real heading lines are
  interleaved with the file lines, which would confuse treesitter for the
  original filetype. Deferred: virtual-line headings + `vim.treesitter.start`
  for highlighted content.
