---GraphQL query strings for the forge subsystem.
---@class AnvilForgeQueries
local M = {}

local PULL_REQUEST_FIELDS = [[
        id
        number
        title
        state
        isDraft
        author {
          login
        }
        headRefName
        baseRefName
        updatedAt
        url
        labels(first: 20) {
          nodes {
            name
            color
          }
        }
        assignees(first: 20) {
          nodes {
            login
          }
        }
        milestone {
          title
        }
        reviewRequests(first: 20) {
          nodes {
            requestedReviewer {
              ... on User {
                login
              }
              ... on Team {
                name
                slug
              }
            }
          }
        }
        reactionGroups {
          content
          users {
            totalCount
          }
        }
        reviewDecision]]

local ISSUE_FIELDS = [[
        id
        number
        title
        state
        author {
          login
        }
        updatedAt
        url
        labels(first: 20) {
          nodes {
            name
            color
          }
        }
        assignees(first: 20) {
          nodes {
            login
          }
        }
        milestone {
          title
        }
        reactionGroups {
          content
          users {
            totalCount
          }
        }]]

local DISCUSSION_FIELDS = [[
        id
        number
        title
        body
        updatedAt
        url
        author {
          login
        }
        category {
          name
        }
        reactionGroups {
          content
          users {
            totalCount
          }
        }
        comments(first: 100) {
          nodes {
            id
            author {
              login
            }
            body
            createdAt
            updatedAt
            url
            reactionGroups {
              content
              users {
                totalCount
              }
            }
          }
        }]]

local COMMENT_FIELDS = [[
          nodes {
            id
            author {
              login
            }
            body
            createdAt
            updatedAt
            url
            reactionGroups {
              content
              users {
                totalCount
              }
            }
          }]]

local REVIEW_FIELDS = [[
          nodes {
            author {
              login
            }
            body
            state
            submittedAt
            url
          }]]

local REVIEW_THREAD_FIELDS = [[
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          comments(first: 100) {
            nodes {
              id
              author {
                login
              }
              body
              createdAt
              updatedAt
              url
              diffHunk
              reactionGroups {
                content
                users {
                  totalCount
                }
              }
            }
          }
        }]]

---Paginated query for open pull requests, most recently updated first.
M.pullreqs = ([[
query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 100, after: $cursor, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
  }
}]]):format(PULL_REQUEST_FIELDS)

---Paginated query for open issues, most recently updated first.
M.issues = ([[
query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $cursor, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
  }
}]]):format(ISSUE_FIELDS)

---Combined query fetching the first page of open pull requests and issues
---in a single round-trip.
M.topics = ([[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 100, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
    issues(first: 100, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
    discussions(first: 100, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
  }
}]]):format(PULL_REQUEST_FIELDS, ISSUE_FIELDS, DISCUSSION_FIELDS)

---Paginated query for discussions, most recently updated first.
M.discussions = ([[
query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    discussions(first: 100, after: $cursor, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
%s
      }
    }
  }
}]]):format(DISCUSSION_FIELDS)

---Detailed query for one pull request, including body, comments, and reviews.
M.pullreq_detail = ([[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
%s
      body
      comments(first: 100) {
%s
      }
      reviews(first: 100, states: [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING]) {
%s
      }
      reviewThreads(first: 100) {
%s
      }
    }
  }
}]]):format(PULL_REQUEST_FIELDS, COMMENT_FIELDS, REVIEW_FIELDS, REVIEW_THREAD_FIELDS)

M.reply_review_thread = [[
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment {
      id
    }
  }
}]]

M.resolve_review_thread = [[
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread {
      id
      isResolved
    }
  }
}]]

M.unresolve_review_thread = [[
mutation($threadId: ID!) {
  unresolveReviewThread(input: {threadId: $threadId}) {
    thread {
      id
      isResolved
    }
  }
}]]

M.add_discussion_comment = [[
mutation($discussionId: ID!, $body: String!) {
  addDiscussionComment(input: {discussionId: $discussionId, body: $body}) {
    comment {
      id
    }
  }
}]]

M.update_discussion = [[
mutation($discussionId: ID!, $title: String, $body: String) {
  updateDiscussion(input: {discussionId: $discussionId, title: $title, body: $body}) {
    discussion {
      id
    }
  }
}]]

M.close_discussion = [[
mutation($discussionId: ID!) {
  closeDiscussion(input: {discussionId: $discussionId}) {
    discussion {
      id
      closed
    }
  }
}]]

M.reopen_discussion = [[
mutation($discussionId: ID!) {
  reopenDiscussion(input: {discussionId: $discussionId}) {
    discussion {
      id
      closed
    }
  }
}]]

M.add_reaction = [[
mutation($subjectId: ID!, $content: ReactionContent!) {
  addReaction(input: {subjectId: $subjectId, content: $content}) {
    reaction {
      content
    }
  }
}]]

M.add_pull_request_review = [[
mutation($pullRequestId: ID!, $body: String, $event: PullRequestReviewEvent, $comments: [DraftPullRequestReviewComment!]) {
  addPullRequestReview(input: {pullRequestId: $pullRequestId, body: $body, event: $event, comments: $comments}) {
    pullRequestReview {
      id
      state
    }
  }
}]]

---Detailed query for one issue, including body and comments.
M.issue_detail = ([[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
%s
      body
      comments(first: 100) {
%s
      }
    }
  }
}]]):format(ISSUE_FIELDS, COMMENT_FIELDS)

---Detailed query for one discussion, including body and comments.
M.discussion_detail = ([[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    discussion(number: $number) {
%s
    }
  }
}]]):format(DISCUSSION_FIELDS)

return M
