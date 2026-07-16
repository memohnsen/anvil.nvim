local PopupBuilder = require("anvil.lib.popup.builder")
local Buffer = require("anvil.lib.buffer")
local logger = require("anvil.logger")
local util = require("anvil.lib.util")
local state = require("anvil.lib.state")
local input = require("anvil.lib.input")
local notification = require("anvil.lib.notification")
local Watcher = require("anvil.watcher")

local FuzzyFinderBuffer = require("anvil.buffers.fuzzy_finder")

local git = require("anvil.lib.git")

local a = require("anvil.lib.async")

local filter_map = util.filter_map
local build_reverse_lookup = util.build_reverse_lookup

local ui = require("anvil.lib.popup.ui")

---@class PopupState

---@class PopupData
---@field state PopupState
---@field buffer Buffer
local M = {}

-- Create a new popup builder
---@return PopupBuilder
function M.builder()
  return PopupBuilder.new(M.new)
end

---@param state PopupState
---@return PopupData
function M.new(state)
  local instance = {
    state = state,
    buffer = nil,
  }
  setmetatable(instance, { __index = M })

  return instance
end

-- Returns the numeric prefix argument the action was invoked with (Neovim's
-- count, the analog of magit's `C-u`). 0 when no prefix was given.
---@return integer
function M:get_prefix()
  return self.state.prefix or 0
end

-- Whether the action was invoked with a non-zero numeric prefix argument.
---@return boolean
function M:has_prefix()
  return (self.state.prefix or 0) > 0
end

-- Returns a table of strings, each representing a toggled option/switch in the popup. Filters out internal arguments.
-- Formatted for consumption by cli:
-- Option: --name=value
-- Switch: --name
---@return string[]
function M:get_arguments()
  local flags = {}

  for _, arg in pairs(self.state.args) do
    if arg.type == "switch" and arg.enabled and not arg.internal then
      table.insert(flags, arg.cli_prefix .. arg.cli .. arg.cli_suffix)
    end

    if arg.type == "option" and arg.cli ~= "" and (arg.value and #arg.value ~= 0) and not arg.internal then
      table.insert(flags, arg.cli_prefix .. arg.cli .. "=" .. arg.value)
    end
  end

  return flags
end

---@param key string
---@return any|nil
function M:get_env(key)
  if not self.state.env then
    return nil
  end

  return self.state.env[key]
end

-- Returns a table of key/value pairs, where the key is the name of the switch, and value is `true`, for all
-- enabled arguments that are NOT for cli consumption (internal use only).
---@return table
function M:get_internal_arguments()
  local args = {}
  for _, arg in pairs(self.state.args) do
    if arg.type == "switch" and arg.enabled and arg.internal then
      args[arg.cli] = true
    end
  end
  return args
end

-- Combines all cli arguments into a single string.
---@return string
function M:to_cli()
  return table.concat(self:get_arguments(), " ")
end

---@param arg PopupOption|PopupSwitch
---@return string|nil
local function state_key_for_arg(arg)
  if arg.type == "switch" and arg.options then
    return arg.cli_suffix
  elseif arg.type == "switch" or arg.type == "option" then
    return arg.cli
  end
end

---@return table
function M:argument_snapshot()
  local snapshot = {}

  for _, arg in ipairs(self.state.args) do
    if arg.id and (arg.type == "switch" or arg.type == "option") then
      snapshot[arg.id] = {
        type = arg.type,
        cli = arg.cli,
        value = arg.value,
        enabled = arg.enabled,
      }
    end
  end

  return snapshot
end

---@param snapshot table
function M:apply_argument_snapshot(snapshot)
  if type(snapshot) ~= "table" then
    return
  end

  for _, arg in ipairs(self.state.args) do
    local saved = arg.id and snapshot[arg.id]
    if saved then
      if arg.type == "switch" then
        arg.cli = saved.cli or arg.cli_base
        arg.value = saved.value or arg.cli
        arg.enabled = saved.enabled == true
      elseif arg.type == "option" then
        arg.value = saved.value or ""
      end
    end
  end
end

function M:save_defaults()
  for _, arg in ipairs(self.state.args) do
    local key = state_key_for_arg(arg)
    if key then
      if arg.type == "switch" and arg.options then
        state.set({ self.state.name, key }, arg.enabled and arg.cli or "")
      elseif arg.type == "switch" then
        state.set({ self.state.name, key }, arg.enabled == true)
      elseif arg.type == "option" then
        state.set({ self.state.name, key }, arg.value or "")
      end
    end
  end

  notification.info(("Saved defaults for %s"):format(self.state.name))
end

function M:reset_defaults()
  for _, arg in ipairs(self.state.args) do
    local key = state_key_for_arg(arg)
    if key then
      state.unset({ self.state.name, key })
    end

    if arg.type == "switch" then
      arg.cli = arg.cli_base
      arg.value = arg.cli
      arg.enabled = false
    elseif arg.type == "option" then
      arg.value = tostring(arg.default or "")
    end
  end

  notification.info(("Reset defaults for %s"):format(self.state.name))
end

local function snapshots_equal(a_snapshot, b_snapshot)
  return vim.deep_equal(a_snapshot, b_snapshot)
end

function M:record_history()
  local snapshot = self:argument_snapshot()
  local history = state.get({ self.state.name, "history" }, {})
  if type(history) ~= "table" then
    history = {}
  end

  if #history == 0 or not snapshots_equal(history[1], snapshot) then
    table.insert(history, 1, snapshot)
  end

  while #history > 20 do
    table.remove(history)
  end

  state.set({ self.state.name, "history" }, history)
  state.set({ self.state.name, "history-index" }, 1)
end

function M:restore_previous_history()
  local history = state.get({ self.state.name, "history" }, {})
  if type(history) ~= "table" or #history == 0 then
    notification.warn(("No history for %s"):format(self.state.name))
    return
  end

  local index = tonumber(state.get({ self.state.name, "history-index" }, 1)) or 1
  index = index + 1
  if index > #history then
    index = 1
  end

  self:apply_argument_snapshot(history[index])
  state.set({ self.state.name, "history-index" }, index)
  notification.info(("Restored history %d/%d for %s"):format(index, #history, self.state.name))
end

-- Closes the popup buffer
function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end
end

-- Transient display levels cycled by `C-x l`, mirroring magit's low/default/all
-- levels. Suffixes tagged above the current level are hidden.
M.LEVELS = { 1, 4, 7 }

-- Cycle the transient display level (magit `C-x l`).
---@return nil
function M:cycle_level()
  local current = self.state.display_level or 4
  local next_level = M.LEVELS[1]
  for i, level in ipairs(M.LEVELS) do
    if level == current then
      next_level = M.LEVELS[(i % #M.LEVELS) + 1]
      break
    end
  end

  self.state.display_level = next_level
end

-- Toggle a switch on/off
---@param switch PopupSwitch
---@return nil
function M:toggle_switch(switch)
  if switch.options then
    local options = build_reverse_lookup(filter_map(switch.options, function(option)
      if option.condition and not option.condition() then
        return
      end

      return option.value
    end))

    local index = options[switch.cli or ""]
    switch.cli = options[(index + 1)] or options[1]
    switch.value = switch.cli
    switch.enabled = switch.cli ~= ""

    if switch.persisted ~= false then
      state.set({ self.state.name, switch.cli_suffix }, switch.cli)
    end

    return
  end

  switch.enabled = not switch.enabled

  -- If a switch depends on user input, i.e. `-Gsomething`, prompt user to get input
  if switch.user_input then
    if switch.enabled then
      local value = input.get_user_input(switch.cli_prefix .. switch.cli_base, { separator = "" })
      if value then
        switch.cli = switch.cli_base .. value
      end
    else
      switch.cli = switch.cli_base
    end
  end

  if switch.persisted ~= false then
    state.set({ self.state.name, switch.cli }, switch.enabled)
  end

  -- Ensure that other switches/options that are incompatible with this one are disabled
  if switch.enabled and #switch.incompatible > 0 then
    for _, var in ipairs(self.state.args) do
      if switch.incompatible[var.cli] then
        if var.type == "switch" then
          ---@cast var PopupSwitch
          self:disable_switch(var)
        elseif var.type == "option" then
          ---@cast var PopupOption
          self:disable_option(var)
        end
      end
    end
  end

  -- Ensure that switches/options that depend on this one are also disabled
  if not switch.enabled and #switch.dependent > 0 then
    for _, var in ipairs(self.state.args) do
      if switch.dependent[var.cli] then
        if var.type == "switch" then
          ---@cast var PopupSwitch
          self:disable_switch(var)
        elseif var.type == "option" then
          ---@cast var PopupOption
          self:disable_option(var)
        end
      end
    end
  end
end

-- Toggle an option on/off and set it's value
---@param option PopupOption
---@param value? string
---@return nil
function M:set_option(option, value)
  if option.value and option.value ~= "" then -- Toggle option off when it's currently set
    option.value = ""
  elseif value then
    option.value = value
  elseif option.choices then
    local eventignore = vim.o.eventignore
    vim.o.eventignore = "WinLeave"
    option.value = FuzzyFinderBuffer.new(option.choices):open_async {
      prompt_prefix = option.description,
      refocus_status = false,
    }
    vim.o.eventignore = eventignore
  elseif option.fn then
    option.value = option.fn(self, option)
  else
    option.value = input.get_user_input(option.cli, {
      separator = "=",
      default = option.value,
      cancel = option.value,
    })
  end

  state.set({ self.state.name, option.cli }, option.value)

  -- Ensure that other switches/options that are incompatible with this one are disabled
  if option.value and option.value ~= "" and #option.incompatible > 0 then
    for _, var in ipairs(self.state.args) do
      if option.incompatible[var.cli] then
        if var.type == "switch" then
          self:disable_switch(var --[[@as PopupSwitch]])
        elseif var.type == "option" then
          self:disable_option(var --[[@as PopupOption]])
        end
      end
    end
  end

  -- Ensure that switches/options that depend on this one are also disabled
  if option.value and option.value ~= "" and #option.dependent > 0 then
    for _, var in ipairs(self.state.args) do
      if option.dependent[var.cli] then
        if var.type == "switch" then
          self:disable_switch(var --[[@as PopupSwitch]])
        elseif var.type == "option" then
          self:disable_option(var --[[@as PopupOption]])
        end
      end
    end
  end
end

---Disables a switch.
---@param switch PopupSwitch
function M:disable_switch(switch)
  if switch.enabled then
    self:toggle_switch(switch)
  end
end

---Disables an option, setting its value to "". Doesn't use the default, which
---is important to ensure that we don't use incompatible switches/options
---together.
---@param option PopupOption
function M:disable_option(option)
  if option.value and option.value ~= "" then
    self:set_option(option, "")
  end
end

-- Set a config value
---@param config PopupConfig
---@return nil
function M:set_config(config)
  if config.options then
    local options = build_reverse_lookup(filter_map(config.options, function(option)
      if option.condition and not option.condition() then
        return
      end

      return option.value
    end))

    local index = options[config.value or ""] or math.huge
    config.value = options[(index + 1)] or options[1]
    git.config.set(config.name, config.value)
  elseif config.fn then
    config.value = config.fn(self, config)
  else
    local result = input.get_user_input(config.name, { default = config.value, cancel = config.value })

    assert(result, "no input from user - what happened to the default?")
    config.value = result
    git.config.set(config.name, config.value)
  end

  for _, var in ipairs(self.state.config) do
    if var.passive then
      local c_value = git.config.get(var.name)
      if c_value:is_set() then
        var.value = c_value.value
      end
    end
  end

  if config.callback then
    config.callback(self, config)
  end
end

M.__lock = a.control.Semaphore.new(1)

function M:mappings()
  local mappings = {
    n = {
      ["q"] = function()
        self:close()
      end,
      ["<esc>"] = function()
        self:close()
      end,
      ["<tab>"] = a.void(function()
        local component = self.buffer.ui:get_interactive_component_under_cursor()
        if not component then
          return
        end

        if component.options.tag == "Switch" then
          self:toggle_switch(component.options.value)
        elseif component.options.tag == "Config" then
          self:set_config(component.options.value)
        elseif component.options.tag == "Option" then
          self:set_option(component.options.value)
        end

        self:refresh()
      end),
      ["<C-x>s"] = function()
        self:save_defaults()
        self:refresh()
      end,
      ["<C-x>p"] = function()
        self:restore_previous_history()
        self:refresh()
      end,
      ["<C-x>r"] = function()
        self:reset_defaults()
        self:refresh()
      end,
      ["<C-x>l"] = function()
        self:cycle_level()
        self:refresh()
      end,
    },
  }

  local arg_prefixes = {}
  for _, arg in pairs(self.state.args) do
    if arg.id and (arg.level or 1) <= (self.state.display_level or 4) then
      arg_prefixes[arg.key_prefix] = true
      mappings.n[arg.id] = a.void(function()
        if arg.type == "switch" then
          ---@cast arg PopupSwitch
          self:toggle_switch(arg)
        elseif arg.type == "option" then
          ---@cast arg PopupOption
          self:set_option(arg)
        end

        self:refresh()
      end)
    end
  end

  for prefix, _ in pairs(arg_prefixes) do
    mappings.n[prefix] = function()
      local c = vim.fn.getcharstr()
      if mappings.n[prefix .. c] then
        mappings.n[prefix .. c]()
      end
    end
  end

  for _, config in pairs(self.state.config) do
    -- selene: allow(empty_if)
    if config.heading then
      -- nothing
    elseif not config.passive then
      mappings.n[config.id] = a.void(function()
        self:set_config(config)
        self:refresh()
        Watcher.instance():dispatch_refresh()
      end)
    end
  end

  -- Multi-key actions must not rely on Neovim's mapping timeout. In
  -- particular, letting `V` time out before `Vs` puts a popup into Visual Line
  -- mode; the next key then attempts to edit its deliberately read-only buffer.
  -- Dispatch prefixes ourselves so every chord waits for its next key.
  local action_mappings = {}
  local action_prefixes = {}

  for _, group in pairs(self.state.actions) do
    for _, action in pairs(group) do
      if not action.heading and action.keys then
        for _, key in ipairs(action.keys) do
          if action.callback then
            action_mappings[key] = a.void(function()
              -- Capture the numeric prefix (Neovim's analog of magit's `C-u`)
              -- synchronously before any await or close, so actions can branch on
              -- it via `popup:get_prefix()` / `popup:has_prefix()`.
              self.state.prefix = vim.v.count

              logger.debug(string.format("[POPUP]: Invoking action %q of %s", key, self.state.name))
              if not action.persist_popup then
                logger.debug("[POPUP]: Closing popup")
                self:close()
              end

              local permit = M.__lock:acquire()
              self:record_history()
              local ok, err = pcall(action.callback, self)
              permit:forget()

              if not ok then
                logger.error(("[POPUP] %s failed: %s"):format(key, err))
              end

              Watcher.instance():dispatch_refresh()
            end)
          else
            action_mappings[key] = function()
              notification.warn(action.description .. " has not been implemented yet")
            end
          end

          for i = 1, #key - 1 do
            action_prefixes[key:sub(1, i)] = true
          end
        end
      end
    end
  end

  local function dispatch_action(prefix)
    local suffix = vim.fn.getcharstr()
    local key = prefix .. suffix
    if action_mappings[key] then
      action_mappings[key]()
    elseif action_prefixes[key] then
      dispatch_action(key)
    end
  end

  for key, callback in pairs(action_mappings) do
    if #key == 1 and not action_prefixes[key] then
      mappings.n[key] = callback
    end
  end

  for prefix, _ in pairs(action_prefixes) do
    mappings.n[prefix] = function()
      dispatch_action(prefix)
    end
  end

  return mappings
end

function M:refresh()
  if self.buffer then
    self.buffer.ui:render(unpack(ui.Popup(self.state)))
  end
end

---@return boolean
function M.is_open()
  return (M.instance and M.instance.buffer and M.instance.buffer:is_visible()) == true
end

function M:show()
  if M.is_open() then
    logger.debug("[POPUP] An Instance is already open - closing it")
    M.instance:close()
  end

  M.instance = self

  self.buffer = Buffer.create {
    name = self.state.name,
    filetype = "AnvilPopup",
    kind = "popup",
    mappings = self:mappings(),
    status_column = " ",
    autocmds = {
      ["WinLeave"] = function()
        pcall(self.close, self)
      end,
    },
    after = function(buf)
      buf:set_window_option("cursorline", false)
      buf:set_window_option("list", false)

      if self.state.env.highlight then
        for i = 1, #self.state.env.highlight, 1 do
          vim.fn.matchadd("AnvilPopupBranchName", self.state.env.highlight[i], 100)
        end
      else
        vim.fn.matchadd("AnvilPopupBranchName", git.repo.state.head.branch, 100)
      end

      if self.state.env.bold then
        for i = 1, #self.state.env.bold, 1 do
          vim.fn.matchadd("AnvilPopupBold", self.state.env.bold[i], 100)
        end
      end

      local height = vim.fn.line("$") + 1
      vim.cmd.resize(height)

      -- We do it again because things like the BranchConfigPopup come from an async context,
      -- but if we only do it schedule wrapped, then you can see it load at one size, and
      -- resize a few ms later
      vim.schedule(function()
        if buf:is_focused() then
          vim.cmd.resize(height)
          buf:set_window_option("winfixheight", true)
        end
      end)
    end,
    render = function()
      return ui.Popup(self.state)
    end,
  }
end

return M
