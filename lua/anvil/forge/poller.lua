local M = {}

local timer

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

---@param opts table|nil
function M.setup(opts)
  stop_timer()
  opts = opts or {}

  if not opts.poll then
    return
  end

  local interval = tonumber(opts.interval) or 300000
  if interval <= 0 then
    return
  end

  timer = vim.uv.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    require("anvil.forge").pull_notifications(function(success)
      if not success then
        return
      end

      local ok, watcher = pcall(require, "anvil.watcher")
      if ok then
        watcher.instance():dispatch_refresh()
      end
    end)
  end))
end

function M.stop()
  stop_timer()
end

return M
