> Detailed Forge (GitHub) reference. See the [README](../README.md) for install and basics.

# Forge

The forge subsystem integrates GitHub into the status buffer and popup system, the same way
[Forge](https://github.com/magit/forge) integrates with Magit. It is inspired by (and
follows the architecture of) [octo.nvim](https://github.com/pwntester/octo.nvim).

**Requirements:** the [GitHub CLI](https://cli.github.com/) (`gh`) installed and
authenticated (`gh auth login`), and a GitHub remote named `origin` or `upstream`.
Everything degrades gracefully when these aren't present: no sections render and
popup actions explain what's missing.

**How it works:** topics are kept in a local store (`stdpath("data")/anvil/forge/`),
so the status buffer renders instantly and offline; the network is only touched when
you sync. If `kkharji/sqlite.lua` is installed, Anvil uses SQLite; otherwise it
falls back to the JSON store. This mirrors Forge's local-database design.

Open the forge popup with `N` from any Anvil buffer (or `:Anvil forge`):

| Key   | Action                                                      |
|-------|-------------------------------------------------------------|
| `f f` | Pull open PRs, issues, and discussions into the local store  |
| `f n` | Pull GitHub notifications into the local store               |
| `f u` | Pull upstream topics into the local store (fork repos only)  |
| `c i` | Create issue (in-editor Markdown composer)                  |
| `c p` | Create pull request (in-editor Markdown composer)           |
| `c d` | Create discussion (in-editor Markdown composer)             |
| `b I` | Browse issues on the web                                    |
| `b P` | Browse pull requests on the web                             |
| `b r` | Browse repository on the web                                |
| `b b` | Browse current branch on the web                            |
| `l t` | List topics (picker), open selection in browser             |
| `l d` | List discussions in a Anvil buffer                         |
| `l n` | List notifications in a Anvil buffer                       |
| `b f` | Checkout a pull request branch (`gh pr checkout`)           |

After a sync, **Pull requests** and **Issues** sections appear in the status buffer
(configurable via `sections.pullreqs` / `sections.issues`). **Discussions** are synced
too, but `sections.discussions.hidden` defaults to `true`, matching Forge's optional
discussion sections. Rows carry the topic URL, so `Y` yanks it.

Topic view buffers render stored descriptions, comments, and PR reviews. Press `f` in a
topic buffer to pull fresh detail for that issue or pull request. Issue and pull request
topic buffers also support `c` comment with a multi-line post editor, `e` edit title,
`b` edit body in a multi-line editor, `l` add labels,
`a` add assignees, `m` set milestone, `+` add a reaction, and `s` toggle open/closed state through `gh`
(the `N` forge popup Topic group additionally offers `t c` close as completed, `t n` close as not
planned, and `t D` close as duplicate for issues, mirroring Forge's topic state commands);
pull request topic buffers additionally support `r` add reviewers, `R` remove reviewers,
`V` queue a pending review comment, `A` approve, `v` submit a comment review, and `X`
request changes; successful edits refresh the local topic detail.
For diffview-backed reviews, the `N` forge popup Review group offers `V s` start a PR review
(opens the pull request's `base...head` diff in your diff viewer), `V c` queue a pending comment
on the diff line under the cursor (file path and LEFT/RIGHT side are derived from the diff window),
and `V S` submit the queued review as comment/approve/request-changes.
Local Forge topic marks are available with `M` mark read, `u` mark unread, `*` save/unsave,
and `d` mark done; list and status buffers show `U`/`S`/`D` markers. The `N` forge popup Topic
group also offers `t N` to set or clear a local freetext note on a topic (forge's topic-notes).
Topic list buffers default to active topics; use `A` all, `U` unread, `S` saved, `D` done,
`O` open, `C` closed, `a` author, `r` assignee, `l` label, and `m` milestone filters.
Press `s` to cycle the tablist sort column (number, updated, state, title) and `i` to invert
the sort direction; the active sort is shown in the buffer header.
Pull request topic detail also renders inline review threads with file/line context, diff hunks,
resolution state, and comments. Use `i` to reply to a numbered review thread, `x` to resolve it,
and `U` to mark it unresolved. Comment and reply editors submit on write or the commit-editor
submit mapping. Use `C` to react to a numbered topic comment and `I` to react to a numbered
review-thread comment. Suggested changes in review comments are listed in the topic buffer; use
`S` to apply a numbered suggestion to the local worktree.

Notification buffers support `r` mark read, `u` mark unread, `s` save/unsave, `d` mark
done, `g` refresh, `A`/`U`/`S`/`D` filter all/unread/saved/done, `t` toggle the
repository-grouped (nested) style, and `o` open the
notification target. Read/unread/save/done state is stored locally;
mark-read also updates GitHub when `gh` is available and authenticated.
See [PLAN.md](../PLAN.md).

Notification polling is opt-in:

```lua
require("anvil").setup({
  forge = {
    notifications = {
      poll = true,
      interval = 300000,
    },
  },
})
```

By default notifications update only when you press `N f n` or `g` inside the notification buffer.
