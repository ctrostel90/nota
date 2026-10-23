-- omnifunc (<C-x><C-o>) for notes; set on note buffers when `completion.omnifunc` is on.
local core = require("notes.completion.core")

local M = {}

local pending

function M.complete(findstart, base)
  if findstart == 1 then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    pending = core.context(0, row, col, vim.api.nvim_get_current_line())
    -- -3: cancel silently when not after `#` or `[[`.
    return pending and pending.start or -3
  end
  if not pending then
    return {}
  end
  local items = core.items(pending)
  if base ~= "" then
    items = vim.fn.matchfuzzy(items, base, { key = "filter" })
  end
  return vim.tbl_map(function(item)
    return { word = item.insert, abbr = item.label, menu = item.detail }
  end, items)
end

function M.attach(buf)
  if core.enabled(buf) then
    vim.bo[buf].omnifunc = "v:lua.require'notes.completion.omni'.complete"
  end
end

return M
