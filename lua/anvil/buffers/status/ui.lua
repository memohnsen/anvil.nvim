local Ui = require("anvil.lib.ui")
local Component = require("anvil.lib.ui.component")
local util = require("anvil.lib.util")
local common = require("anvil.buffers.common")
local config = require("anvil.config")
local a = require("anvil.lib.async")
local state = require("anvil.lib.state")
local event = require("anvil.lib.event")

local col = Ui.col
local row = Ui.row
local text = Ui.text

local map = util.map

local EmptyLine = common.EmptyLine
local List = common.List
local DiffHunks = common.DiffHunks

local M = {}

local HINT = Component.new(function(props)
  ---@return table<string, string[]>
  local function reversed_lookup(tbl)
    local result = {}
    for k, v in pairs(tbl) do
      if v then
        local current = result[v]
        if current then
          table.insert(current, k)
        else
          result[v] = { k }
        end
      end
    end

    return result
  end

  local reversed_status_map = reversed_lookup(props.config.mappings.status)
  local reversed_popup_map = reversed_lookup(props.config.mappings.popup)

  local entry = function(name, hint)
    local keys = reversed_status_map[name] or reversed_popup_map[name]
    local key_hint

    if keys and #keys > 0 then
      key_hint = table.concat(keys, " ")
    else
      key_hint = "<unmapped>"
    end

    return row {
      text.highlight("AnvilPopupActionKey")(key_hint),
      text(" "),
      text(hint),
    }
  end

  return row {
    text.highlight("AnvilSubtleText")("Hint: "),
    entry("Toggle", "toggle"),
    text.highlight("AnvilSubtleText")(" | "),
    entry("Stage", "stage"),
    text.highlight("AnvilSubtleText")(" | "),
    entry("Unstage", "unstage"),
    text.highlight("AnvilSubtleText")(" | "),
    entry("Discard", "discard"),
    text.highlight("AnvilSubtleText")(" | "),
    entry("CommitPopup", "commit"),
    text.highlight("AnvilSubtleText")(" | "),
    entry("HelpPopup", "help"),
  }
end)

local HEAD = Component.new(function(props)
  local show_oid = props.show_oid
  local highlight, ref
  if props.branch == "(detached)" then
    highlight = "AnvilBranch"
    ref = props.branch
    show_oid = true
  elseif props.remote then
    highlight = "AnvilRemote"
    ref = ("%s/%s"):format(props.remote, props.branch)
  else
    highlight = "AnvilBranch"
    ref = props.branch
  end

  local oid = props.yankable
  if not oid or oid == "(initial)" then
    oid = "0000000"
  else
    oid = oid:sub(1, 7)
  end

  return row({
    text.highlight("AnvilStatusHEAD")(util.pad_right(props.name .. ": ", props.HEAD_padding)),
    text.highlight("AnvilObjectId")(show_oid and oid or ""),
    text(show_oid and " " or ""),
    text.highlight(highlight)(ref),
    text(" "),
    text(props.msg or "(no commits)"),
  }, { yankable = props.yankable })
end)

local Tag = Component.new(function(props)
  if props.distance then
    return row({
      text.highlight("AnvilStatusHEAD")(util.pad_right("Tag: ", props.HEAD_padding)),
      text.highlight("AnvilTagName")(props.name),
      text(" ("),
      text.highlight("AnvilTagDistance")(props.distance),
      text(")"),
    }, { yankable = props.yankable })
  else
    return row({
      text(util.pad_right("Tag: ", props.HEAD_padding)),
      text.highlight("AnvilTagName")(props.name),
    }, { yankable = props.yankable })
  end
end)

local SectionTitle = Component.new(function(props)
  return { text.highlight(props.highlight or "AnvilSectionHeader")(props.title) }
end)

local SectionTitleRemote = Component.new(function(props)
  return {
    text.highlight(props.highlight or "AnvilSectionHeader")(props.title),
    text(" "),
    text.highlight("AnvilRemote")(props.ref),
  }
end)

local SectionTitleRebase = Component.new(function(props)
  if props.onto then
    return {
      text.highlight(props.highlight or "AnvilSectionHeader")(props.title),
      text(" "),
      text.highlight("AnvilBranch")(props.head),
      text.highlight("AnvilSectionHeader")(" onto "),
      text.highlight(props.is_remote_ref and "AnvilRemote" or "AnvilBranch")(props.onto),
    }
  else
    return {
      text.highlight(props.highlight or "AnvilSectionHeader")(props.title),
      text(" "),
      text.highlight("AnvilBranch")(props.head),
    }
  end
end)

local SectionTitleMerge = Component.new(function(props)
  return {
    text.highlight(props.highlight or "AnvilSectionHeader")(props.title),
    text(" "),
    text.highlight("AnvilBranch")(props.branch),
  }
end)

local Section = Component.new(function(props)
  local count
  if props.count then
    count = { text(" ("), text.highlight("AnvilSectionHeaderCount")(#props.items), text(")") }
  end

  return col.tag("Section")({
    row(util.merge(props.title, count or {})),
    col(map(props.items, props.render)),
    EmptyLine(),
  }, {
    foldable = true,
    folded = props.folded,
    section = props.name,
    id = props.name,
  })
end)

local SequencerSection = Component.new(function(props)
  return col.tag("Section")({
    row(util.merge(props.title)),
    col(map(props.items, props.render)),
    EmptyLine(),
  }, {
    foldable = true,
    folded = props.folded,
    section = props.name,
    id = props.name,
  })
end)

local RebaseSection = Component.new(function(props)
  return col.tag("Section")({
    row(util.merge(props.title, {
      text(" ("),
      text(props.current),
      text("/"),
      text(#props.items - 1),
      text(")"),
    })),
    col(map(props.items, props.render)),
    EmptyLine(),
  }, {
    foldable = true,
    folded = props.folded,
    section = props.name,
    id = props.name,
  })
end)

local SectionItemFile = function(section, config)
  return Component.new(function(item)
    local load_diff = function(item)
      ---@param this Component
      ---@param ui Ui
      ---@param prefix string|nil
      return a.void(function(this, ui, prefix)
        this.options.on_open = nil
        this.options.folded = false

        local row, _ = this:row_range_abs()
        row = row + 1 -- Filename row

        local diff = item.diff
        for _, hunk in ipairs(diff.hunks) do
          hunk.first = row
          hunk.last = row + hunk.length
          row = hunk.last + 1

          -- Set fold state when called from ui:update()
          if prefix then
            local key = ("%s--%s"):format(prefix, hunk.hash)
            if ui._node_fold_state and ui._node_fold_state[key] then
              hunk._folded = ui._node_fold_state[key].folded
            end
          end
        end

        ui.buf:with_locked_viewport(function()
          this:append(DiffHunks(diff))
          ui:update()
        end)

        event.send("DiffLoaded", {
          item = {
            absolute_path = item.absolute_path,
            relative_path = item.escaped_path,
            row_start = item.first,
            row_end = item.last,
            mode = item.mode,
          },
          diff = {
            kind = diff.kind,
            lines = diff.lines,
            hunks = util.map(diff.hunks, function(hunk)
              local original_lines = util.filter_map(hunk.lines, function(line)
                if not (vim.startswith(line, "+") or vim.startswith(line, "-")) then
                  return line
                end
              end)

              local modified_lines = util.map(hunk.lines, function(line)
                return line:gsub("^[+-]", " ")
              end)

              return {
                lines = hunk.lines,
                original_lines = original_lines,
                modified_lines = modified_lines,
                row_start = hunk.first,
                row_end = hunk.last,
                header = hunk.line,
              }
            end),
          },
        })
      end)
    end

    local mode = config.status.mode_text[item.mode]
    local mode_text
    if mode == "" then
      mode_text = ""
    elseif config.status.mode_padding > 0 then
      mode_text = util.pad_right(
        mode,
        util.max_length(vim.tbl_values(config.status.mode_text)) + config.status.mode_padding
      )
    end

    local unmerged_types = {
      ["DD"] = " (both deleted)",
      ["DU"] = " (deleted by us)",
      ["UD"] = " (deleted by them)",
      ["AA"] = " (both added)",
      ["AU"] = " (added by us)",
      ["UA"] = " (added by them)",
    }

    local name = item.original_name and ("%s -> %s"):format(item.original_name, item.name) or item.name
    local highlight = ("AnvilChange%s%s"):format(item.mode:gsub("%?", "Untracked"), section)

    local file_mode_change = text("")
    if
      item.file_mode
      and item.file_mode.worktree ~= item.file_mode.head
      and tonumber(item.file_mode.head) > 0
    then
      file_mode_change =
        text.highlight("AnvilSubtleText")((" %s -> %s"):format(item.file_mode.head, item.file_mode.worktree))
    end

    local submodule = text("")
    if item.submodule then
      local submodule_text
      if item.submodule.commit_changed then
        submodule_text = " (new commits)"
      elseif item.submodule.has_tracked_changes then
        submodule_text = " (modified content)"
      elseif item.submodule.has_untracked_changes then
        submodule_text = " (untracked content)"
      end

      submodule = text.highlight("AnvilTagName")(submodule_text)
    end

    return col.tag("Item")({
      row {
        text.highlight(highlight)(mode_text),
        text(name),
        text.highlight("AnvilSubtleText")(unmerged_types[item.mode] or ""),
        file_mode_change,
        submodule,
      },
    }, {
      foldable = true,
      folded = true,
      on_open = load_diff(item),
      context = true,
      id = ("%s--%s"):format(section, item.name),
      yankable = item.name,
      filename = item.name,
      item = item,
    })
  end)
end

local SectionItemForgeTopic = Component.new(function(item)
  local prefix = item.kind == "pullreq" and "PR" or item.kind == "discussion" and "D" or "#"
  local marks = (item.unread and "U" or " ") .. (item.saved and "S" or " ") .. (item.done and "D" or " ")
  return row({
    text.highlight("AnvilSubtleText")(marks),
    text(" "),
    text.highlight("AnvilBranch")(("%s%d"):format(prefix, item.number)),
    text(" "),
    text(item.title or ""),
    text.highlight("AnvilSubtleText")(item.draft and " (draft)" or ""),
  }, { yankable = item.url, url = item.url, item = item })
end)

local SectionItemWip = Component.new(function(item)
  local name = (item.ref or ""):gsub("^refs/wip/", "")
  return row({
    text.highlight("AnvilObjectId")(item.oid or ""),
    text(" "),
    text.highlight("AnvilBranch")(name),
    text.highlight("AnvilSubtleText")(item.date and (" " .. item.date) or ""),
    text(" "),
    text(item.message or ""),
  }, { yankable = item.ref, oid = item.ref, item = item })
end)

local SectionItemStash = Component.new(function(item)
  local name = ("stash@{%s}"):format(item.idx)
  return row({
    text.highlight("AnvilSubtleText")(name),
    text.highlight("AnvilSubtleText")(": "),
    text(item.message),
  }, { yankable = item.oid, item = item })
end)

local SectionItemCommit = Component.new(function(item)
  local ref = {}
  local ref_last = {}

  if item.commit.ref_name ~= "" and state.get({ "AnvilMarginPopup", "decorate" }, true) then
    -- Render local only branches first
    for name, _ in pairs(item.decoration.locals) do
      if name:match("^refs/") then
        table.insert(ref_last, text(name, { highlight = "AnvilGraphGray" }))
        table.insert(ref_last, text(" "))
      elseif item.decoration.remotes[name] == nil then
        local branch_highlight = item.decoration.head == name and "AnvilBranchHead" or "AnvilBranch"
        table.insert(ref, text(name, { highlight = branch_highlight }))
        table.insert(ref, text(" "))
      end
    end

    -- Render tracked (local+remote) branches next
    for name, remotes in pairs(item.decoration.remotes) do
      if #remotes == 1 then
        table.insert(ref, text(remotes[1] .. "/", { highlight = "AnvilRemote" }))
      end

      if #remotes > 1 then
        table.insert(ref, text("{" .. table.concat(remotes, ",") .. "}/", { highlight = "AnvilRemote" }))
      end

      local branch_highlight = item.decoration.head == name and "AnvilBranchHead" or "AnvilBranch"
      local locally = item.decoration.locals[name] ~= nil
      table.insert(ref, text(name, { highlight = locally and branch_highlight or "AnvilRemote" }))
      table.insert(ref, text(" "))
    end

    -- Render tags
    for _, tag in pairs(item.decoration.tags) do
      table.insert(ref, text(tag, { highlight = "AnvilTagName" }))
      table.insert(ref, text(" "))
    end
  end

  local virtual_text

  -- Render margin, if visible
  if state.get({ "margin", "visibility" }, true) then
    local is_shortstat = state.get({ "margin", "shortstat" }, false)

    if is_shortstat then
      local cli_shortstat = item.shortstat
      local files_changed
      local insertions
      local deletions

      files_changed = cli_shortstat:match("^ (%d+) files?")
      files_changed = util.str_min_width(files_changed, 3, nil, { mode = "insert" })
      insertions = cli_shortstat:match("(%d+) insertions?")
      insertions = util.str_min_width(insertions and insertions .. "+" or " ", 5, nil, { mode = "insert" })
      deletions = cli_shortstat:match("(%d+) deletions?")
      deletions = util.str_min_width(deletions and deletions .. "-" or " ", 5, nil, { mode = "insert" })

      virtual_text = {
        { " ", "Constant" },
        { insertions, "AnvilDiffAdditions" },
        { " ", "Constant" },
        { deletions, "AnvilDiffDeletions" },
        { " ", "Constant" },
        { files_changed, "AnvilSubtleText" },
      }
    else -- Author & date margin
      local margin_date_style = state.get({ "margin", "date_style" }, 1)
      local details = state.get({ "margin", "details" }, true)

      local date
      local rel_date
      local date_width = 10
      local clamp_width = 30 -- to avoid having too much space when relative date is short

      -- Render date
      if item.commit.rel_date:match(" years?,") then
        rel_date, _ = item.commit.rel_date:gsub(" years?,", "y")
        rel_date = rel_date .. " "
      elseif item.commit.rel_date:match("^%d ") then
        rel_date = " " .. item.commit.rel_date
      else
        rel_date = item.commit.rel_date
      end

      if margin_date_style == 1 then -- relative date (short)
        local unpacked = vim.split(rel_date, " ")

        -- above, we added a space if the rel_date started with a single number
        -- we get the last two elements to deal with that
        local date_number = unpacked[#unpacked - 1]
        local date_quantifier = unpacked[#unpacked]
        if date_quantifier:match("months?") then
          date_quantifier = date_quantifier:gsub("m", "M") -- to distinguish from minutes
        end

        -- add back the space if we have a single number
        local left_pad
        if #unpacked > 2 then
          left_pad = " "
        else
          left_pad = ""
        end

        date = left_pad .. date_number .. util.str_first_char(date_quantifier)
        date_width = 3
        clamp_width = 23
      elseif margin_date_style == 2 then -- relative date (long)
        date = rel_date
        date_width = 10
      else -- local iso date
        if config.values.log_date_format == nil then
          -- we get the unix date to be able to convert the date to the local timezone
          date = os.date("%Y-%m-%d %H:%M", item.commit.unix_date)
          date_width = 16 -- width of "YYYY-MM-DD HH:MM"
        else
          date = item.commit.log_date
          date_width = 16
        end
      end

      local author_table = { "" }
      if details then
        author_table = {
          util.str_clamp(item.commit.author_name, clamp_width - (#date > date_width and #date or date_width)),
          "AnvilGraphAuthor",
        }
      end

      virtual_text = {
        { " ", "Constant" },
        author_table,
        { util.str_min_width(date, date_width), "Special" },
      }
    end
  end

  return row(
    util.merge(
      { text.highlight("AnvilObjectId")(item.commit.abbreviated_commit) },
      { text(" ") },
      ref,
      ref_last,
      { text(item.commit.subject) }
    ),
    {
      virtual_text = virtual_text,
      oid = item.commit.oid,
      yankable = item.commit.oid,
      item = item,
    }
  )
end)

local SectionItemRebase = Component.new(function(item)
  if item.oid then
    local action_hl = (item.done and "AnvilRebaseDone")
      or (item.action == "onto" and "AnvilGraphBlue")
      or "AnvilGraphOrange"

    return row({
      text(item.stopped and "> " or "  "),
      text.highlight(action_hl)(util.pad_right(item.action, 6)),
      text(" "),
      text.highlight("AnvilRebaseDone")(item.abbreviated_commit),
      text(" "),
      text.highlight(item.done and "AnvilRebaseDone")(item.subject),
    }, { yankable = item.oid, oid = item.oid })
  else
    return row {
      text.highlight("AnvilGraphOrange")(item.action),
      text(" "),
      text(item.subject),
    }
  end
end)

local SectionItemSequencer = Component.new(function(item)
  local action_hl = (item.action == "join" and "AnvilGraphRed")
    or (item.action == "onto" and "AnvilGraphBlue")
    or "AnvilGraphOrange"

  local show_action = #item.action > 0
  local action = show_action and util.pad_right(item.action, 6) or ""

  return row({
    text.highlight(action_hl)(action),
    text(show_action and " " or ""),
    text.highlight("AnvilObjectId")(item.abbreviated_commit),
    text(" "),
    text(item.subject),
  }, { yankable = item.oid, oid = item.oid })
end)

local SectionItemBisect = Component.new(function(item)
  local highlight
  if item.action == "good" then
    highlight = "AnvilGraphGreen"
  elseif item.action == "bad" then
    highlight = "AnvilGraphRed"
  elseif item.finished then
    highlight = "AnvilGraphBoldOrange"
  end

  return row({
    text(item.finished and "> " or "  "),
    text.highlight(highlight)(util.pad_right(item.action, 5)),
    text(" "),
    text.highlight("AnvilObjectId")(item.abbreviated_commit),
    text(" "),
    text(item.subject),
  }, { yankable = item.oid, oid = item.oid })
end)

local BisectDetailsSection = Component.new(function(props)
  return col.tag("Section")({
    row(util.merge(props.title, { text(" "), text.highlight("AnvilObjectId")(props.commit.oid) })),
    row {
      text.highlight("AnvilSubtleText")("Author:     "),
      text((props.commit.author_name or "") .. " <" .. (props.commit.author_email or "") .. ">"),
    },
    row { text.highlight("AnvilSubtleText")("AuthorDate: "), text(props.commit.author_date) },
    row {
      text.highlight("AnvilSubtleText")("Committer:  "),
      text((props.commit.committer_name or "") .. " <" .. (props.commit.committer_email or "") .. ">"),
    },
    row { text.highlight("AnvilSubtleText")("CommitDate: "), text(props.commit.committer_date) },
    EmptyLine(),
    col(
      map(props.commit.description, text),
      { highlight = "AnvilCommitViewDescription", tag = "Description" }
    ),
    EmptyLine(),
  }, {
    foldable = true,
    folded = props.folded,
    section = props.name,
    yankable = props.commit.oid,
    id = props.name,
  })
end)

function M.Status(state, config)
  -- stylua: ignore start
  local show_hint = not config.disable_hint

  local show_upstream = state.upstream.ref
    and not state.head.detached

  local show_pushRemote = state.pushRemote.ref
    and not state.head.detached

  local show_tag = state.head.tag.name

  local show_tag_distance = state.head.tag.name
    and not state.head.detached

  local show_merge = state.merge.head
    and not config.sections.sequencer.hidden

  local show_rebase = #state.rebase.items > 0
    and not config.sections.rebase.hidden

  local show_cherry_pick = state.sequencer.cherry_pick
    and not config.sections.sequencer.hidden

  local show_revert = state.sequencer.revert
    and not config.sections.sequencer.hidden

  local show_bisect = #state.bisect.items > 0
    and not config.sections.bisect.hidden

  local show_untracked = #state.untracked.items > 0
    and not config.sections.untracked.hidden

  local show_unstaged = #state.unstaged.items > 0
    and not config.sections.unstaged.hidden

  local show_staged = #state.staged.items > 0
    and not config.sections.staged.hidden

  local show_upstream_unpulled = #state.upstream.unpulled.items > 0
    and not config.sections.unpulled_upstream.hidden

  local show_pushRemote_unpulled = #state.pushRemote.unpulled.items > 0
    and state.pushRemote.ref ~= state.upstream.ref
    and not config.sections.unpulled_pushRemote.hidden

  local show_upstream_unmerged = #state.upstream.unmerged.items > 0
    and not config.sections.unmerged_upstream.hidden

  local show_pushRemote_unmerged = #state.pushRemote.unmerged.items > 0
    and state.pushRemote.ref ~= state.upstream.ref
    and not config.sections.unmerged_pushRemote.hidden

  local show_stashes = #state.stashes.items > 0
    and not config.sections.stashes.hidden

  local show_recent = #state.recent.items > 0
    and not config.sections.recent.hidden

  local wip_config = config.sections.wip or { folded = true, hidden = false }
  local show_wip = #state.wip.items > 0
    and not wip_config.hidden

  local forge_topics = { pullreqs = {}, issues = {}, discussions = {} }
  local upstream_topics = { pullreqs = {}, issues = {}, discussions = {} }
  do
    local ok, forge = pcall(require, "anvil.forge")
    if ok then
      local topics_ok, topics = pcall(forge.topics)
      if topics_ok and topics then
        forge_topics = topics
      end

      local up_ok, up = pcall(forge.upstream_topics)
      if up_ok and up then
        upstream_topics = up
      end
    end
  end

  local pullreqs_config = config.sections.pullreqs or { folded = true, hidden = false }
  local issues_config = config.sections.issues or { folded = true, hidden = false }
  local discussions_config = config.sections.discussions or { folded = true, hidden = true }

  local show_pullreqs = #forge_topics.pullreqs > 0
    and not pullreqs_config.hidden

  local show_issues = #forge_topics.issues > 0
    and not issues_config.hidden

  local show_discussions = #forge_topics.discussions > 0
    and not discussions_config.hidden

  local upstream_label = upstream_topics.repo and (" (" .. upstream_topics.repo .. ")") or ""
  local show_upstream_pullreqs = #upstream_topics.pullreqs > 0 and not pullreqs_config.hidden
  local show_upstream_issues = #upstream_topics.issues > 0 and not issues_config.hidden
  local show_upstream_discussions = #upstream_topics.discussions > 0 and not discussions_config.hidden

  return {
    List {
      items = {
        show_hint and HINT { config = config },
        show_hint and EmptyLine(),
        col.tag("Section")({
          HEAD {
            name = "Head",
            branch = state.head.branch,
            oid = state.head.abbrev,
            msg = state.head.commit_message,
            yankable = state.head.oid,
            show_oid = config.status.show_head_commit_hash,
            HEAD_padding = config.status.HEAD_padding,
          },
          show_upstream and HEAD {
            name = "Merge",
            branch = state.upstream.branch,
            remote = state.upstream.remote,
            msg = state.upstream.commit_message,
            yankable = state.upstream.oid,
            show_oid = config.status.show_head_commit_hash,
            HEAD_padding = config.status.HEAD_padding,
          },
          show_pushRemote and HEAD {
            name = "Push",
            branch = state.pushRemote.branch,
            remote = state.pushRemote.remote,
            msg = state.pushRemote.commit_message,
            yankable = state.pushRemote.oid,
            show_oid = config.status.show_head_commit_hash,
            HEAD_padding = config.status.HEAD_padding,
          },
          show_tag and Tag {
            name = state.head.tag.name,
            distance = show_tag_distance and state.head.tag.distance,
            yankable = state.head.tag.oid,
            HEAD_padding = config.status.HEAD_padding,
          },
        }, { foldable = true, folded = config.status.HEAD_folded }),
        EmptyLine(),
        show_merge and SequencerSection {
          title = SectionTitleMerge {
            title = "Merging",
            branch = state.merge.branch,
            highlight = "AnvilMerging",
          },
          render = SectionItemSequencer,
          items = { { action = "", oid = state.merge.head, subject = state.merge.subject } },
          folded = config.sections.sequencer.folded,
          name = "merge",
        },
        show_rebase and RebaseSection {
          title = SectionTitleRebase {
            title = "Rebasing",
            head = state.rebase.head,
            onto = state.rebase.onto.ref,
            oid = state.rebase.onto.oid,
            is_remote_ref = state.rebase.onto.is_remote,
            highlight = "AnvilRebasing",
          },
          render = SectionItemRebase,
          current = state.rebase.current,
          items = state.rebase.items,
          folded = config.sections.rebase.folded,
          name = "rebase",
        },
        show_cherry_pick and SequencerSection {
          title = SectionTitle { title = "Cherry Picking", highlight = "AnvilPicking" },
          render = SectionItemSequencer,
          items = util.reverse(state.sequencer.items),
          folded = config.sections.sequencer.folded,
          name = "cherry_pick",
        },
        show_revert and SequencerSection {
          title = SectionTitle { title = "Reverting", highlight = "AnvilReverting" },
          render = SectionItemSequencer,
          items = util.reverse(state.sequencer.items),
          folded = config.sections.sequencer.folded,
          name = "revert",
        },
        show_bisect and BisectDetailsSection {
          title = SectionTitle { title = "Bisecting at", highlight = "AnvilBisecting" },
          commit = state.bisect.current,
          folded = config.sections.bisect.folded,
          name = "bisect_details",
        },
        show_bisect and SequencerSection {
          title = SectionTitle { title = "Bisecting Log", highlight = "AnvilBisecting" },
          render = SectionItemBisect,
          items = state.bisect.items,
          folded = config.sections.bisect.folded,
          name = "bisect",
        },
        show_untracked and Section {
          title = SectionTitle { title = "Untracked files", highlight = "AnvilUntrackedfiles" },
          count = true,
          render = SectionItemFile("untracked", config),
          items = state.untracked.items,
          folded = config.sections.untracked.folded,
          name = "untracked",
        },
        show_unstaged and Section {
          title = SectionTitle { title = "Unstaged changes", highlight = "AnvilUnstagedchanges" },
          count = true,
          render = SectionItemFile("unstaged", config),
          items = state.unstaged.items,
          folded = config.sections.unstaged.folded,
          name = "unstaged",
        },
        show_staged and Section {
          title = SectionTitle { title = "Staged changes", highlight = "AnvilStagedchanges" },
          count = true,
          render = SectionItemFile("staged", config),
          items = state.staged.items,
          folded = config.sections.staged.folded,
          name = "staged",
        },
        show_stashes and Section {
          title = SectionTitle { title = "Stashes", highlight = "AnvilStashes" },
          count = true,
          render = SectionItemStash,
          items = state.stashes.items,
          folded = config.sections.stashes.folded,
          name = "stashes",
        },
        show_wip and Section {
          title = SectionTitle { title = "WIP snapshots", highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemWip,
          items = state.wip.items,
          folded = wip_config.folded,
          name = "wip",
        },
        show_upstream_unmerged and Section {
          title = SectionTitleRemote {
            title = "Unmerged into",
            ref = state.upstream.ref,
            highlight = "AnvilUnmergedchanges",
          },
          count = true,
          render = SectionItemCommit,
          items = state.upstream.unmerged.items,
          folded = config.sections.unmerged_upstream.folded,
          name = "upstream_unmerged",
        },
        show_pushRemote_unmerged and Section {
          title = SectionTitleRemote {
            title = "Unpushed to",
            ref = state.pushRemote.ref,
            highlight = "AnvilUnpushedchanges",
          },
          count = true,
          render = SectionItemCommit,
          items = state.pushRemote.unmerged.items,
          folded = config.sections.unmerged_pushRemote.folded,
          name = "pushRemote_unmerged",
        },
        not show_upstream_unmerged and show_recent and Section {
          title = SectionTitle { title = "Recent Commits", highlight = "AnvilRecentcommits" },
          count = false,
          render = SectionItemCommit,
          items = state.recent.items,
          folded = config.sections.recent.folded,
          name = "recent",
        },
        show_upstream_unpulled and Section {
          title = SectionTitleRemote {
            title = "Unpulled from",
            ref = state.upstream.ref,
            highlight = "AnvilUnpulledchanges",
          },
          count = true,
          render = SectionItemCommit,
          items = state.upstream.unpulled.items,
          folded = config.sections.unpulled_upstream.folded,
          name = "upstream_unpulled",
        },
        show_pushRemote_unpulled and Section {
          title = SectionTitleRemote {
            title = "Unpulled from",
            ref = state.pushRemote.ref,
            highlight = "AnvilUnpulledchanges",
          },
          count = true,
          render = SectionItemCommit,
          items = state.pushRemote.unpulled.items,
          folded = config.sections.unpulled_pushRemote.folded,
          name = "pushRemote_unpulled",
        },
        show_pullreqs and Section {
          title = SectionTitle { title = "Pull requests", highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = forge_topics.pullreqs,
          folded = pullreqs_config.folded,
          name = "pullreqs",
        },
        show_issues and Section {
          title = SectionTitle { title = "Issues", highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = forge_topics.issues,
          folded = issues_config.folded,
          name = "issues",
        },
        show_discussions and Section {
          title = SectionTitle { title = "Discussions", highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = forge_topics.discussions,
          folded = discussions_config.folded,
          name = "discussions",
        },
        show_upstream_pullreqs and Section {
          title = SectionTitle { title = "Upstream pull requests" .. upstream_label, highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = upstream_topics.pullreqs,
          folded = pullreqs_config.folded,
          name = "upstream_pullreqs",
        },
        show_upstream_issues and Section {
          title = SectionTitle { title = "Upstream issues" .. upstream_label, highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = upstream_topics.issues,
          folded = issues_config.folded,
          name = "upstream_issues",
        },
        show_upstream_discussions and Section {
          title = SectionTitle { title = "Upstream discussions" .. upstream_label, highlight = "AnvilSectionHeader" },
          count = true,
          render = SectionItemForgeTopic,
          items = upstream_topics.discussions,
          folded = discussions_config.folded,
          name = "upstream_discussions",
        },
      },
    },
  }
end

-- stylua: ignore end

return M
