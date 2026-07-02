# Plan: A Magit + Forge Clone for Neovim

Goal: evolve this Neogit fork into an exact functional clone of **magit** (git porcelain) with
**forge** (GitHub/GitLab integration) baked in as a first-class subsystem — the way forge extends
magit's status buffer and keymaps — using **octo.nvim** as the reference (and code donor) for the
GitHub client layer.

Reference repos reviewed:
- `magit/magit` — 47 elisp modules, ~50 transient prefixes ("popups")
- `magit/forge` — forge layer: local SQLite topic database, status-buffer sections, topic buffers, notifications, multi-forge support
- `TimUntersberger/NeoGit` fork (this repo) — 23 popups, status/log/refs/reflog/commit/stash buffers
- `pwntester/octo.nvim` — gh-CLI/GraphQL client, issue/PR/discussion buffers, full PR review flow

---

## Current status

This repository now has the Magit/Forge scaffolding in place, with the highest-value git
porcelain gaps implemented:

- `!` run popup with arbitrary git/shell commands and WIP snapshot actions.
- Magit-compatible status popup defaults for `!`, `N`, `z`, `Z`, `W`, `T`, `O`, `C`, `h`, and `e`.
- Blame buffer, patch/am, notes, submodule popup/list buffer, clone, file-dispatch,
  sparse-checkout, subtree, bundle, shortlog, repos, dispatch, and mergetool popups.
- Commit popup instant fixup/squash and absorb flows.
- WIP refs with manual commands plus opt-in automatic before/after snapshots around mutating
  Neogit git operations, with a WIP snapshot list/apply buffer.
- Forge GitHub client through `gh`, local JSON store with optional SQLite backend, status sections,
  topic buffers, topic list buffers, notification buffer, discussions, PR checkout/worktree,
  topic-buffer comment/title/body/label/assignee/milestone/state/reviewer edits, inline PR
  review thread rendering/replies/resolution, topic/comment/review-thread comment reactions,
  suggested-change application, multi-line post/body/reply editing, pending PR review comments,
  review submit/approve/request-changes actions, and common issue/PR lifecycle actions, plus
  local topic marks (read/unread/save/done), notification filtering/manual refresh, and opt-in
  notification polling.
- README/vimdoc coverage and regression tests for docs, config, keymaps, popups, Forge store/list
  buffers, topic buffers, command completion, and WIP behavior.

Remaining work is no longer "add the missing popup shells"; it is deeper parity: full Magit
transient semantics, diffview-backed PR review browsing/comment placement, and multi-forge
backends beyond GitHub.

---

## Part 1 — Magit parity gaps (git core)

Neogit already covers: status, commit, log, diff, branch (+config), push, pull, fetch, merge,
rebase, cherry-pick, revert, reset, stash, tag, remote (+config), bisect, worktree, ignore,
reflog, refs view, margin, yank, git command history, interactive rebase editor.

### Popup/command parity

| Magit feature | What it does | Priority |
|---|---|---|
| `magit-blame` | Implemented as a blame buffer; remaining parity: all style variants and exact cycling commands | Medium |
| `magit-patch` / `magit-am` | Implemented popup shell and common patch/am commands | Done |
| `magit-submodule` | Implemented popup shell, common submodule commands, and list buffer actions | Done |
| `magit-notes` | Implemented popup shell and common notes commands | Done |
| `magit-run` / `magit-git-command` | Implemented `!` popup with repo/current-dir git and shell commands | Done |
| `magit-file-dispatch` | Implemented file-oriented dispatch popup | Done |
| `magit-dispatch` | Implemented global dispatch popup | Done |
| `magit-ediff` / mergetool | Implemented mergetool popup delegating to git/diff integrations | Done |
| `magit-commit-absorb` / autofixup | Implemented `git absorb` integration when available | Done |
| Instant fixup/squash (`c F`, `c S`) | Implemented commit + immediate autosquash rebase | Done |
| `magit-sparse-checkout` | Implemented sparse-checkout popup | Done |
| `magit-subtree` | Implemented subtree popup | Done |
| `magit-bundle` | Implemented bundle popup | Done |
| `magit-shortlog` | Implemented shortlog popup | Done |
| `magit-wip` modes | Implemented manual refs, opt-in automatic before/after snapshots, and WIP list/apply UX | Done |
| `magit-repos` | Implemented repositories overview popup/list | Done |
| `magit-clone` popup | Implemented clone popup | Done |
| Revision buffer niceties | `magit-revision-jump`, diff-refresh popup (`D`), log-refresh (`L`) in-buffer | Medium |
| `magit-reflog` popups | Neogit has reflog view; verify checkout/reset actions from it match magit | Low |

### Behavioral/UX parity to audit

- **Section model**: Magit-style `n`/`p`/`^` section navigation and `M-1..M-4`
  section depth aliases are implemented; remaining parity is deeper universal section
  machinery beyond the status buffer.
- **Point preservation & refresh** semantics after every operation.
- **Prefix arguments** — magit uses `C-u` variants everywhere (e.g. `C-u y` refs, `C-u F` pull
  elsewhere). Define a consistent neovim idiom (count or `g`-prefixed variants) and apply it
  across all popups.
- **`magit-process-mode`** parity: `$` process buffer with sections per command, kill process —
  neogit has a console; verify feature-for-feature.
- **Transient parity**: popup argument defaults (`C-x s`), history cycling (`C-x p`), and
  reset (`C-x r`) are implemented through shared popup state; remaining parity is transient
  level filtering (`C-x l`) and exact Magit suffix-level display semantics.
- **Bookmark/jump equivalents**: `magit-status-jump` (`j` jump-to-section) exists? Verify.

---

## Part 2 — Forge baked in (the big one)

Forge's architecture, translated to Lua:

### 2.1 Data layer (forge-db.el → `lua/neogit/forge/db.lua`)
- Forge keeps a **local SQLite database** of repos/topics/posts so everything renders instantly
  offline and fetches are incremental. Neovim option: bundle `sqlite.lua` (kkharji) as optional
  dep, with a JSON-file fallback store (`stdpath("data")/neogit/forge/<repo-hash>.json`).
- Schema: repository, pullreq, issue, discussion, post/comment, review, label, milestone,
  assignee, notification, mark — mirror forge's closql schema.
- Incremental sync: store `updated_at` cursors per repo; `forge-pull` fetches only changed topics.

### 2.2 Client layer (forge-github.el / octo `gh/` → `lua/neogit/forge/client/`)
- **Adopt octo.nvim's approach**: shell out to `gh` CLI for auth + GraphQL. Port/adapt octo's
  `gh/graphql.lua`, `queries.lua`, `mutations.lua`, `fragments.lua` — this is the highest-leverage
  code reuse available; it's battle-tested against GitHub's API.
- Abstract behind a `Forge` interface (like forge's class hierarchy: github, gitlab, gitea,
  forgejo, gogs, bitbucket). **Phase 1: GitHub only** via gh CLI; interface designed so GitLab
  (`glab` CLI or REST) can slot in later.
- GitHub Enterprise / multiple hosts support (octo already does per-host auth).

### 2.3 Status buffer integration (forge.el's magit-status-sections-hook)
- New status sections rendered from the local DB (no network on refresh):
  - **Pull requests** (open PRs, unread markers)
  - **Issues**
  - **Discussions** (optional, off by default like forge)
- `<CR>` on a topic opens the topic buffer; sections respect neogit's fold/hide config
  (`config.sections.pullreqs`, `config.sections.issues`).
- Unread/pending status indicators (forge's topic status: unread/pending/done).

### 2.4 Forge popup (forge-dispatch → `lua/neogit/popups/forge/`)
Bound to `N` (forge's default binding under magit) with subgroups mirroring `forge-dispatch`:
- **Fetch**: `f f` pull topics for repo, `f n` pull notifications
- **Create**: `c i` issue, `c p` pull request, `c d` discussion, `c P` post/comment
- **Browse**: `b` browse topic/repo/commit/branch/blob at point on the web
- **Visit**: `v` visit topic/repo
- **List**: `l i` issues, `l p` pullreqs, `l d` discussions, `l n` notifications, `l r` repos
- **Checkout**: `b p`-style checkout PR branch, checkout PR into **worktree**
- **PR lifecycle**: merge (method select), approve, request-changes, mark ready/draft,
  `forge-branch-pullreq`, `create-pullreq-from-issue`, push to unnamed PR
- **Topic editing** (topic menu when in topic buffer): set title, labels, assignees, milestone,
  review requests, local marks/save/unsave; remaining deeper states: merged/unplanned/duplicate
  and note workflows.

### 2.5 Topic buffers (forge-topic.el + octo's issue/PR buffers)
- A rendered buffer per issue/PR/discussion: title, metadata table (state, labels, milestone,
  assignees, review requests, marks), description, comment timeline, review threads.
- **Port octo's buffer model** (`octo/model/`, `ui/`, writers) but restyle to magit-section
  aesthetics: foldable sections per comment, neogit keymaps, edit-in-place fields.
- Post editing via neogit's existing editor buffer machinery (like commit editor): compose
  comment/reply/review in a split, `:w` + close submits (matching forge's post buffers,
  `C-c C-c` semantics).
- Topic/comment/review-thread comment reactions and resolving threads are implemented;
  suggested-change application, pending review comments, review submission, and multi-line post
  editing are implemented.

### 2.6 PR review flow (octo/reviews/ — forge itself is weak here, octo is stronger)
- Port octo's review subsystem: start/resume/submit review, file panel, side-by-side diff via
  diffview integration, inline comment threads on left/right, pending comments.
  Initial pending-comment queueing and review submission (`APPROVE`, `COMMENT`,
  `REQUEST_CHANGES`) are implemented in topic buffers; remaining work is diffview-backed file
  browsing and exact left/right placement from the diff UI.
- This *exceeds* forge (forge users typically drop to the browser for reviews) — keep it, it's
  the killer feature of baking octo in.

### 2.7 Notifications (forge-notify.el / octo notifications)
- Notification list buffer with all/unread/saved/done filters, unread markers,
  mark read/done/save, manual refresh, and opt-in polling is implemented; remaining
  parity: nested styles.

### 2.8 Topic list buffers (forge-topics.el / forge-tablist)
- `forge-list-*` equivalents: dedicated list buffers and fuzzy-finder pickers exist; remaining
  parity is advanced Forge tablist-style sorting/columns; filters by state, author, assignee,
  label, milestone, and marks are implemented.

---

## Part 3 — Suggested implementation order

1. **Foundation (magit quick wins)** — `!` run popup, instant fixup/squash in commit popup,
   file-dispatch, blame. Small, high-daily-value, no new architecture.
2. **Forge skeleton** — `gh` client layer (port octo's gh module), JSON/SQLite store, `forge-pull`
   sync, PR + issue sections in status buffer, `N` popup with fetch/browse/visit/list.
3. **Topic buffers** — read-only render first, then mutations (comment, edit fields, state).
4. **PR lifecycle** — create PR/issue, checkout PR (+worktree), merge/approve/request-changes.
5. **Review flow** — port octo reviews onto diffview.
6. **Notifications + topic list buffers.**
7. **Remaining magit parity** — submodule, patch/am, notes, wip, repos list, clone popup,
   sparse-checkout/subtree/bundle/shortlog.
8. **Polish pass** — keybinding audit vs magit defaults, transient save/history semantics,
   prefix-arg idiom, docs (`:h neogit-forge`), vimdoc for every popup.

## Part 4 — Key design decisions (recommendations)

- **gh CLI, not raw tokens**: follow octo — auth via `gh`, GraphQL via `gh api graphql`. Zero
  credential handling in the plugin.
- **Port octo code, don't depend on octo**: the user experience must be one plugin with one
  section/keymap/popup system. Vendor and restyle octo's gh layer, buffer writers, and review
  engine into `lua/neogit/forge/`; drop octo's separate `:Octo` command surface (optionally keep
  a thin `:Neogit forge ...` command).
- **Local-first like forge**: render from the store, sync explicitly (`N f f`) or on timer.
  This is forge's defining trait vs octo (octo fetches on demand) — adopt forge's model.
- **SQLite optional**: `sqlite.lua` if available, JSON fallback, same store API.
- **Multi-forge interface from day one, GitHub implementation only** — matches forge's
  class hierarchy without boiling the ocean.
