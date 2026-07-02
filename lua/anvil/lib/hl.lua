--#region TYPES

---@class HiSpec
---@field fg string
---@field bg string
---@field gui string
---@field sp string
---@field blend integer
---@field default boolean

---@class HiLinkSpec
---@field force boolean
---@field default boolean

--#endregion

local Color = require("anvil.lib.color").Color
local hl_store
local M = {}

---@param dec number
---@return string
local function to_hex(dec)
  local hex = string.format("%x", dec)
  if #hex < 6 then
    return string.rep("0", 6 - #hex) .. hex
  else
    return hex
  end
end

---@param name string Syntax group name.
---@return string|nil
local function get_fg(name)
  local color = vim.api.nvim_get_hl(0, { name = name })
  if color["link"] then
    return get_fg(color["link"])
  elseif color["reverse"] and color["bg"] then
    return "#" .. to_hex(color["bg"])
  elseif color["fg"] then
    return "#" .. to_hex(color["fg"])
  end
end

---@param name string Syntax group name.
---@return string|nil
local function get_bg(name)
  local color = vim.api.nvim_get_hl(0, { name = name })
  if color["link"] then
    return get_bg(color["link"])
  elseif color["reverse"] and color["fg"] then
    return "#" .. to_hex(color["fg"])
  elseif color["bg"] then
    return "#" .. to_hex(color["bg"])
  end
end

---@class AnvilColorPalette
---@field bg0        string  Darkest background color
---@field bg1        string  Second darkest background color
---@field bg2        string  Second lightest background color
---@field bg3        string  Lightest background color
---@field grey       string  middle grey shade for foreground
---@field white      string  Foreground white (main text)
---@field red        string  Foreground red
---@field bg_red     string  Background red
---@field line_red   string  Cursor line highlight for red regions, like deleted hunks
---@field orange     string  Foreground orange
---@field bg_orange  string  background orange
---@field yellow     string  Foreground yellow
---@field bg_yellow  string  background yellow
---@field green      string  Foreground green
---@field bg_green   string  Background green
---@field line_green string  Cursor line highlight for green regions, like added hunks
---@field cyan       string  Foreground cyan
---@field bg_cyan    string  Background cyan
---@field blue       string  Foreground blue
---@field bg_blue    string  Background blue
---@field purple     string  Foreground purple
---@field bg_purple  string  Background purple
---@field md_purple  string  Background _medium_ purple. Lighter than bg_purple.
---@field inline_green string  Background for inline add word-diff highlights
---@field inline_red   string  Background for inline delete word-diff highlights
---@field italic     boolean enable italics?
---@field bold       boolean enable bold?
---@field underline  boolean enable underline?

-- stylua: ignore start
---@param config AnvilConfig
---@return AnvilColorPalette
local function make_palette(config)
  local bg        = Color.from_hex(get_bg("Normal") or (vim.o.bg == "dark" and "#22252A" or "#eeeeee"))
  local fg        = Color.from_hex((vim.o.bg == "dark" and "#fcfcfc" or "#22252A"))
  local red       = Color.from_hex(config.highlight.red or get_fg("ErrorMsg") or "#E06C75")
  local orange    = Color.from_hex(config.highlight.orange or get_fg("SpecialChar") or "#ffcb6b")
  local yellow    = Color.from_hex(config.highlight.yellow or get_fg("PreProc") or "#FFE082")
  local green     = Color.from_hex(config.highlight.green or get_fg("String") or "#C3E88D")
  local cyan      = Color.from_hex(config.highlight.cyan or get_fg("Operator") or "#89ddff")
  local blue      = Color.from_hex(config.highlight.blue or get_fg("Macro") or "#82AAFF")
  local purple    = Color.from_hex(config.highlight.purple or get_fg("Include") or "#C792EA")

  local bg_factor = vim.o.bg == "dark" and 1 or -1

  local default   = {
    bg0          = bg:to_css(),
    bg1          = bg:shade(bg_factor * 0.019):to_css(),
    bg2          = bg:shade(bg_factor * 0.065):to_css(),
    bg3          = bg:shade(bg_factor * 0.11):to_css(),
    grey         = bg:shade(bg_factor * 0.4):to_css(),
    white        = fg:to_css(),
    red          = red:to_css(),
    bg_red       = red:shade(bg_factor * -0.18):to_css(),
    line_red     = get_bg("DiffDelete") or red:shade(bg_factor * -0.6):set_saturation(0.4):to_css(),
    orange       = orange:to_css(),
    bg_orange    = orange:shade(bg_factor * -0.17):to_css(),
    yellow       = yellow:to_css(),
    bg_yellow    = yellow:shade(bg_factor * -0.17):to_css(),
    green        = green:to_css(),
    bg_green     = green:shade(bg_factor * -0.18):to_css(),
    line_green   = get_bg("DiffAdd") or green:shade(bg_factor * -0.72):set_saturation(0.2):to_css(),
    cyan         = cyan:to_css(),
    bg_cyan      = cyan:shade(bg_factor * -0.18):to_css(),
    blue         = blue:to_css(),
    bg_blue      = blue:shade(bg_factor * -0.18):to_css(),
    purple       = purple:to_css(),
    bg_purple    = purple:shade(bg_factor * -0.18):to_css(),
    md_purple    = purple:shade(0.18):to_css(),
    inline_green = green:shade(bg_factor * -0.2):set_saturation(0.65):to_css(),
    inline_red   = red:shade(bg_factor * 0.3):set_saturation(0.65):to_css(),
    italic       = true,
    bold         = true,
    underline    = true,
  }

  return vim.tbl_extend("keep", config.highlight or {}, default)
end
-- stylua: ignore end

-- https://github.com/lewis6991/gitsigns.nvim/blob/1e01b2958aebb79f1c33e7427a1bac131a678e0d/lua/gitsigns/highlight.lua#L250
--- @param hl_name string
--- @return boolean
local function is_set(hl_name)
  local exists, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_name })
  if not exists then
    return false
  end

  return not vim.tbl_isempty(hl)
end

---@param config AnvilConfig
function M.setup(config)
  local palette = make_palette(config)

  -- stylua: ignore
  hl_store = {
    AnvilGraphAuthor              = { fg = palette.orange, ctermfg = 3 },
    AnvilGraphRed                 = { fg = palette.red, ctermfg = 1 },
    AnvilGraphWhite               = { fg = palette.white, ctermfg = 7 },
    AnvilGraphYellow              = { fg = palette.yellow, ctermfg = 3 },
    AnvilGraphGreen               = { fg = palette.green, ctermfg = 2 },
    AnvilGraphCyan                = { fg = palette.cyan, ctermfg = 6 },
    AnvilGraphBlue                = { fg = palette.blue, ctermfg = 4 },
    AnvilGraphPurple              = { fg = palette.purple, ctermfg = 5 },
    AnvilGraphGray                = { fg = palette.grey, ctermfg = 7 },
    AnvilGraphOrange              = { fg = palette.orange, ctermfg = 3 },
    AnvilGraphBoldOrange          = { fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    AnvilGraphBoldRed             = { fg = palette.red, bold = palette.bold, ctermfg = 1 },
    AnvilGraphBoldWhite           = { fg = palette.white, bold = palette.bold, ctermfg = 7 },
    AnvilGraphBoldYellow          = { fg = palette.yellow, bold = palette.bold, ctermfg = 3 },
    AnvilGraphBoldGreen           = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    AnvilGraphBoldCyan            = { fg = palette.cyan, bold = palette.bold, ctermfg = 6 },
    AnvilGraphBoldBlue            = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    AnvilGraphBoldPurple          = { fg = palette.purple, bold = palette.bold, ctermfg = 5 },
    AnvilGraphBoldGray            = { fg = palette.grey, bold = palette.bold, ctermfg = 7 },
    AnvilSubtleText               = { link = "Comment" },
    AnvilSignatureGood            = { link = "AnvilGraphGreen" },
    AnvilSignatureBad             = { link = "AnvilGraphBoldRed" },
    AnvilSignatureMissing         = { link = "AnvilGraphPurple" },
    AnvilSignatureNone            = { link = "AnvilSubtleText" },
    AnvilSignatureGoodUnknown     = { link = "AnvilGraphBlue" },
    AnvilSignatureGoodExpired     = { link = "AnvilGraphOrange" },
    AnvilSignatureGoodExpiredKey  = { link = "AnvilGraphYellow" },
    AnvilSignatureGoodRevokedKey  = { link = "AnvilGraphRed" },
    AnvilNormal                   = { link = "Normal" },
    AnvilNormalFloat              = { link = "AnvilNormal" },
    AnvilFloatBorder              = { link = "AnvilNormalFloat" },
    AnvilSignColumn               = { fg = "None", bg = "None" },
    AnvilCursorLine               = { link = "CursorLine" },
    AnvilCursorLineNr             = { link = "CursorLineNr" },
    AnvilHunkMergeHeader          = { fg = palette.bg2, bg = palette.grey, bold = palette.bold, ctermfg = 4 },
    AnvilHunkMergeHeaderHighlight = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    AnvilHunkMergeHeaderCursor    = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    AnvilHunkHeader               = { fg = palette.bg0, bg = palette.grey, bold = palette.bold, ctermfg = 3 },
    AnvilHunkHeaderHighlight      = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    AnvilHunkHeaderCursor         = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    AnvilDiffContext              = { bg = palette.bg1 },
    AnvilDiffContextHighlight     = { bg = palette.bg2 },
    AnvilDiffContextCursor        = { bg = palette.bg1 },
    AnvilDiffAdditions            = { fg = palette.bg_green, ctermfg = 2 },
    AnvilDiffAdd                  = { bg = palette.line_green, fg = palette.bg_green, ctermfg = 2 },
    AnvilDiffAddHighlight         = { bg = palette.line_green, fg = palette.green, ctermfg = 2 },
    AnvilDiffAddCursor            = { bg = palette.bg1, fg = palette.green, ctermfg = 2 },
    AnvilDiffDeletions            = { fg = palette.bg_red, ctermfg = 1 },
    AnvilDiffDelete               = { bg = palette.line_red, fg = palette.bg_red, ctermfg = 1 },
    AnvilDiffDeleteHighlight      = { bg = palette.line_red, fg = palette.red, ctermfg = 1 },
    AnvilDiffDeleteCursor         = { bg = palette.bg1, fg = palette.red, ctermfg = 1 },
    AnvilDiffAddInline            = { bg = palette.inline_green, fg = palette.line_green, bold = palette.bold },
    AnvilDiffDeleteInline         = { bg = palette.inline_red, fg = palette.bg0, bold = palette.bold },
    AnvilPopupSectionTitle        = { link = "Function" },
    AnvilPopupBranchName          = { link = "String" },
    AnvilPopupBold                = { bold = palette.bold },
    AnvilPopupSwitchKey           = { fg = palette.purple, ctermfg = 5 },
    AnvilPopupSwitchEnabled       = { link = "SpecialChar" },
    AnvilPopupSwitchDisabled      = { link = "AnvilSubtleText" },
    AnvilPopupOptionKey           = { fg = palette.purple, ctermfg = 5 },
    AnvilPopupOptionEnabled       = { link = "SpecialChar" },
    AnvilPopupOptionDisabled      = { link = "AnvilSubtleText" },
    AnvilPopupConfigKey           = { fg = palette.purple, ctermfg = 5 },
    AnvilPopupConfigEnabled       = { link = "SpecialChar" },
    AnvilPopupConfigDisabled      = { link = "AnvilSubtleText" },
    AnvilPopupActionKey           = { fg = palette.purple, ctermfg = 5 },
    AnvilPopupActionDisabled      = { link = "AnvilSubtleText" },
    AnvilFilePath                 = { fg = palette.blue, italic = palette.italic, ctermfg = 3 },
    AnvilCommitViewHeader         = { bg = palette.bg_cyan, fg = palette.bg0, ctermfg = 7 },
    AnvilCommitViewDescription    = { link = "String" },
    AnvilDiffHeader               = { bg = palette.bg3, fg = palette.blue, bold = palette.bold, ctermfg = 3 },
    AnvilDiffHeaderHighlight      = { bg = palette.bg3, fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    AnvilCommandText              = { link = "AnvilSubtleText" },
    AnvilCommandTime              = { link = "AnvilSubtleText" },
    AnvilCommandCodeNormal        = { link = "String" },
    AnvilCommandCodeError         = { link = "Error" },
    AnvilBranch                   = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    AnvilBranchHead               = { fg = palette.blue, bold = palette.bold, underline = palette.underline, ctermfg = 4 },
    AnvilRemote                   = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    AnvilUnmergedInto             = { fg = palette.bg_purple, bold = palette.bold, ctermfg = 5 },
    AnvilUnpushedTo               = { fg = palette.bg_purple, bold = palette.bold, ctermfg = 5 },
    AnvilUnpulledFrom             = { fg = palette.bg_purple, bold = palette.bold, ctermfg = 5 },
    AnvilStatusHEAD               = {},
    AnvilObjectId                 = { link = "AnvilSubtleText" },
    AnvilStash                    = { link = "AnvilSubtleText" },
    AnvilRebaseDone               = { link = "AnvilSubtleText" },
    AnvilFold                     = { fg = "None", bg = "None" },
    AnvilFoldColumn               = { fg = "None", bg = "None" },
    AnvilWinSeparator             = { link = "WinSeparator" },
    AnvilChangeMuntracked         = { link = "AnvilChangeModified" },
    AnvilChangeAuntracked         = { link = "AnvilChangeAdded" },
    AnvilChangeNuntracked         = { link = "AnvilChangeNewFile" },
    AnvilChangeDuntracked         = { link = "AnvilChangeDeleted" },
    AnvilChangeCuntracked         = { link = "AnvilChangeCopied" },
    AnvilChangeUuntracked         = { link = "AnvilChangeUpdated" },
    AnvilChangeRuntracked         = { link = "AnvilChangeRenamed" },
    AnvilChangeDDuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeUUuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeAAuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeDUuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeUDuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeAUuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeUAuntracked        = { link = "AnvilChangeUnmerged" },
    AnvilChangeUntrackeduntracked = { fg = "None" },
    AnvilChangeMunstaged          = { link = "AnvilChangeModified" },
    AnvilChangeAunstaged          = { link = "AnvilChangeAdded" },
    AnvilChangeNunstaged          = { link = "AnvilChangeNewFile" },
    AnvilChangeDunstaged          = { link = "AnvilChangeDeleted" },
    AnvilChangeCunstaged          = { link = "AnvilChangeCopied" },
    AnvilChangeUunstaged          = { link = "AnvilChangeUpdated" },
    AnvilChangeRunstaged          = { link = "AnvilChangeRenamed" },
    AnvilChangeTunstaged          = { link = "AnvilChangeUpdated" },
    AnvilChangeDDunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeUUunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeAAunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeDUunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeUDunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeAUunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeUAunstaged         = { link = "AnvilChangeUnmerged" },
    AnvilChangeUntrackedunstaged  = { fg = "None" },
    AnvilChangeMstaged            = { link = "AnvilChangeModified" },
    AnvilChangeAstaged            = { link = "AnvilChangeAdded" },
    AnvilChangeNstaged            = { link = "AnvilChangeNewFile" },
    AnvilChangeDstaged            = { link = "AnvilChangeDeleted" },
    AnvilChangeCstaged            = { link = "AnvilChangeCopied" },
    AnvilChangeUstaged            = { link = "AnvilChangeUpdated" },
    AnvilChangeRstaged            = { link = "AnvilChangeRenamed" },
    AnvilChangeTstaged            = { link = "AnvilChangeUpdated" },
    AnvilChangeDDstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeUUstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeAAstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeDUstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeUDstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeAUstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeUAstaged           = { link = "AnvilChangeUnmerged" },
    AnvilChangeUntrackedstaged    = { fg = "None" },
    AnvilChangeModified           = { fg = palette.bg_blue, bold = palette.bold, italic = palette.italic, ctermfg = 4 },
    AnvilChangeAdded              = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    AnvilChangeDeleted            = { fg = palette.bg_red, bold = palette.bold, italic = palette.italic, ctermfg = 1 },
    AnvilChangeRenamed            = { fg = palette.bg_purple, bold = palette.bold, italic = palette.italic, ctermfg = 5 },
    AnvilChangeUpdated            = { fg = palette.bg_orange, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    AnvilChangeCopied             = { fg = palette.bg_cyan, bold = palette.bold, italic = palette.italic, ctermfg = 6 },
    AnvilChangeUnmerged           = { fg = palette.bg_yellow, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    AnvilChangeNewFile            = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    AnvilSectionHeader            = { fg = palette.bg_purple, bold = palette.bold, ctermfg = 5 },
    AnvilSectionHeaderCount       = {},
    AnvilUntrackedfiles           = { link = "AnvilSectionHeader" },
    AnvilUnstagedchanges          = { link = "AnvilSectionHeader" },
    AnvilUnmergedchanges          = { link = "AnvilSectionHeader" },
    AnvilUnpulledchanges          = { link = "AnvilSectionHeader" },
    AnvilUnpushedchanges          = { link = "AnvilSectionHeader" },
    AnvilRecentcommits            = { link = "AnvilSectionHeader" },
    AnvilStagedchanges            = { link = "AnvilSectionHeader" },
    AnvilStashes                  = { link = "AnvilSectionHeader" },
    AnvilMerging                  = { link = "AnvilSectionHeader" },
    AnvilBisecting                = { link = "AnvilSectionHeader" },
    AnvilRebasing                 = { link = "AnvilSectionHeader" },
    AnvilPicking                  = { link = "AnvilSectionHeader" },
    AnvilReverting                = { link = "AnvilSectionHeader" },
    AnvilTagName                  = { fg = palette.yellow, ctermfg = 3 },
    AnvilTagDistance              = { fg = palette.cyan, ctermfg = 6 },
    AnvilFloatHeader              = { bg = palette.bg0, bold = palette.bold, ctermfg = 5 },
    AnvilFloatHeaderHighlight     = { bg = palette.bg2, fg = palette.cyan, bold = palette.bold, ctermfg = 5 },
    AnvilActiveItem               = { bg = palette.bg_orange, fg = palette.bg0, bold = palette.bold, ctermfg = 5 },
  }

  for group, hl in pairs(hl_store) do
    if not is_set(group) then
      hl.default = true
      vim.api.nvim_set_hl(0, group, hl)
    end
  end
end

return M
