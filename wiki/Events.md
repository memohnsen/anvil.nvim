> Autocmd events emitted by Anvil. See the [README](../README.md) for install and basics.

# Events

Anvil emits the following events:

| Event                   | Description                              | Event Data                                      |
|-------------------------|------------------------------------------|-------------------------------------------------|
| `AnvilStatusRefreshed` | Status has been reloaded                 | `{}`                                            |
| `AnvilCommitComplete`  | Commit has been created                  | `{}`                                            |
| `AnvilPushComplete`    | Push has completed                       | `{}`                                            |
| `AnvilPullComplete`    | Pull has completed                       | `{}`                                            |
| `AnvilFetchComplete`   | Fetch has completed                      | `{}`                                            |
| `AnvilBranchCreate`    | Branch was created, starting from `base` | `{ branch_name: string, base: string? }`        |
| `AnvilBranchDelete`    | Branch was deleted                       | `{ branch_name: string }`                       |
| `AnvilBranchCheckout`  | Branch was checked out                   | `{ branch_name: string }`                       |
| `AnvilBranchReset`     | Branch was reset to a commit/branch      | `{ branch_name: string, resetting_to: string }` |
| `AnvilBranchRename`    | Branch was renamed                       | `{ branch_name: string, new_name: string }`     |
| `AnvilRebase`        | A rebase finished                        | `{ commit: string, status: "ok"\|"conflict" }`    |
| `AnvilReset`         | A branch was reset to a certain commit   | `{ commit: string, mode: "soft"\|"mixed"\|"hard"\|"keep"\|"index" }` |
| `AnvilTagCreate`     | A tag was placed on a certain commit     | `{ name: string, ref: string }`                   |
| `AnvilTagDelete`     | A tag was removed                        | `{ name: string }`                                |
| `AnvilCherryPick`    | One or more commits were cherry-picked    | `{ commits: string[] }`                          |
| `AnvilMerge`         | A merge finished                          | `{ branch: string, args = string[], status: "ok"\|"conflict" }` |
| `AnvilStash`         | A stash finished                          | `{ success: boolean }` |
| `AnvilForgePulled`   | Forge topics were synced from GitHub      | `{}` |
| `AnvilForgePullRequestCheckout` | A PR branch was checked out via the forge popup | `{ number: number }` |
| `AnvilUserCommandComplete` | A command from the run popup finished | `{ cmd: string, cwd: string }` |
