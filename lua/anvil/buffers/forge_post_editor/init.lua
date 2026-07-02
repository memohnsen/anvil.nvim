local Buffer = require("anvil.lib.buffer")
local config = require("anvil.config")
local notification = require("anvil.lib.notification")

local M = {}
M.__index = M

---@param opts table
---@return ForgePostEditor
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    title = opts.title or "Forge Post",
    initial = opts.initial or "",
    on_submit = opts.on_submit or function(_, cb)
      cb(true)
    end,
    on_abort = opts.on_abort,
    buffer = nil,
    submitting = false,
  }, M)
end

function M:body()
  if not self.buffer then
    return ""
  end

  local lines = self.buffer:get_lines(0, -1)
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

function M:submit()
  if self.submitting then
    return
  end

  local body = self:body()
  if body == "" then
    notification.warn("Forge: empty post body")
    return
  end

  self.submitting = true
  self.on_submit(body, function(success, err)
    self.submitting = false
    if not success then
      notification.error("Forge: failed to submit post: " .. (err or "unknown error"))
      return
    end

    if self.buffer then
      self.buffer:set_buffer_option("modified", false)
      self.buffer:close(true)
    end
  end)
end

function M:abort()
  if self.on_abort then
    self.on_abort()
  end

  if self.buffer then
    self.buffer:set_buffer_option("modified", false)
    self.buffer:close(true)
  end
end

---@param kind string|nil
---@return ForgePostEditor
function M:open(kind)
  local mapping = config.get_reversed_commit_editor_maps()
  local mapping_i = config.get_reversed_commit_editor_maps_I()
  local initial = vim.split(self.initial, "\n", { plain = true })
  if #initial == 0 then
    initial = { "" }
  end

  self.buffer = Buffer.create {
    name = ("AnvilForgePost://%s/%d"):format(self.title:gsub("%s+", "-"), vim.uv.hrtime()),
    filetype = "markdown",
    kind = kind or "split",
    modifiable = true,
    readonly = false,
    disable_line_numbers = config.values.disable_line_numbers,
    disable_relative_line_numbers = config.values.disable_relative_line_numbers,
    autocmds = {
      BufWriteCmd = function()
        self:submit()
      end,
    },
    initialize = function(buffer)
      buffer:set_lines(0, -1, false, initial)
      buffer:move_cursor(1)
    end,
    mappings = {
      i = {
        [mapping_i["Submit"]] = function()
          vim.cmd.stopinsert()
          self:submit()
        end,
        [mapping_i["Abort"]] = function()
          vim.cmd.stopinsert()
          self:abort()
        end,
      },
      n = {
        [mapping["Submit"]] = function()
          self:submit()
        end,
        [mapping["Abort"]] = function()
          self:abort()
        end,
        ZZ = function()
          self:submit()
        end,
        ZQ = function()
          self:abort()
        end,
      },
    },
  }

  return self
end

return M
