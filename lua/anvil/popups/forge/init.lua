local popup = require("anvil.lib.popup")
local actions = require("anvil.popups.forge.actions")

local M = {}

function M.create(env)
  -- The eight logical groups are stacked into five columns (smaller groups
  -- paired vertically) so the popup fits on screen instead of running off the
  -- right edge. `group_heading("")` inserts a blank line between stacked groups.
  local p = popup
    .builder()
    :name("AnvilForgePopup")

    -- Column 1: Fetch / Create
    :group_heading("Fetch")
    :action("ff", "all topics", actions.pull)
    :action("fn", "notifications", actions.pull_notifications)
    :action("fu", "upstream topics", actions.pull_upstream)
    :group_heading("")
    :group_heading("Create")
    :action("ci", "issue", actions.create_issue)
    :action("cp", "pull request", actions.create_pull_request)
    :action("cd", "discussion", actions.create_discussion)
    :action("cP", "post/comment", actions.comment_topic)

    -- Column 2: Browse / Checkout
    :new_action_group("Browse")
    :action("bI", "issues", actions.browse_issues)
    :action("bP", "pull requests", actions.browse_pullreqs)
    :action("br", "repository", actions.browse_repo)
    :action("bb", "current branch", actions.browse_branch)
    :action("bt", "topic", actions.browse_topic)
    :group_heading("")
    :group_heading("Checkout")
    :action("bf", "pull request", actions.checkout_pullreq)
    :action("bF", "PR in worktree", actions.checkout_pullreq_worktree)

    -- Column 3: List / Review
    :new_action_group("List")
    :action("li", "issues", actions.list_issues_buffer)
    :action("lp", "pull requests", actions.list_pullreqs_buffer)
    :action("ld", "discussions", actions.list_discussions_buffer)
    :action("lt", "topics", actions.list_topics)
    :action("ln", "notifications", actions.list_notifications)
    :group_heading("")
    :group_heading("Review")
    :action("Vs", "start PR review", actions.start_review)
    :action("Vc", "comment on line", actions.review_comment_at_cursor)
    :action("VS", "submit review", actions.submit_review)

    -- Column 4: Pull request
    :new_action_group("Pull request")
    :action("pm", "merge", actions.merge_pullreq)
    :action("pa", "approve", actions.approve_pullreq)
    :action("pr", "request changes", actions.request_changes_pullreq)
    :action("pR", "mark ready", actions.ready_pullreq)
    :action("pD", "mark draft", actions.draft_pullreq)
    :action("pv", "add reviewers", actions.add_pullreq_reviewers)
    :action("pV", "remove reviewers", actions.remove_pullreq_reviewers)

    -- Column 5: Topic
    :new_action_group("Topic")
    :action("te", "edit title", actions.edit_topic_title)
    :action("tl", "edit labels", actions.edit_topic_labels)
    :action("tb", "edit body", actions.edit_topic_body)
    :action("ta", "add assignees", actions.edit_topic_assignees)
    :action("tm", "set milestone", actions.edit_topic_milestone)
    :action("tr", "add reaction", actions.add_topic_reaction)
    :action("ts", "state open/closed", actions.toggle_topic_state)
    :action("tc", "close as completed", actions.close_topic_completed)
    :action("tn", "close as not planned", actions.close_topic_unplanned)
    :action("tD", "close as duplicate", actions.close_topic_duplicate)
    :action("tM", "mark read", actions.mark_topic_read)
    :action("tu", "mark unread", actions.mark_topic_unread)
    :action("t*", "save", actions.save_topic)
    :action("t_", "unsave", actions.unsave_topic)
    :action("td", "mark done", actions.mark_topic_done)
    :action("tN", "set note", actions.set_topic_note)
    :env(env)
    :build()

  p:show()

  return p
end

return M
