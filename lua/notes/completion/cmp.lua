-- nvim-cmp source, registered as "notes" by setup() when nvim-cmp is installed. Enable it with:
--   sources = cmp.config.sources({ { name = "notes" }, ... })
-- It only activates in notes (markdown files inside the notes dir).
local core = require("notes.completion.core")

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return core.enabled(vim.api.nvim_get_current_buf())
end

function source:get_debug_name()
  return "notes"
end

function source:get_trigger_characters()
  return { "#", "[" }
end

-- textEdit ranges below are byte offsets.
function source:get_position_encoding_kind()
  return "utf-8"
end

-- Keyword starts right after `#` or `[[`, so cmp filters on what follows (incl. `/`, spaces in links).
function source:get_keyword_pattern()
  return [[\%(#\zs[[:alnum:]_/\-]*\|\[\[\zs[^\[\]|#]*\)]]
end

function source:complete(params, callback)
  local row, col = params.context.cursor.row, params.context.cursor.col - 1
  local line = params.context.cursor_line
  local context = core.context(params.context.bufnr, row, col, line)
  if not context then
    return callback({ items = {}, isIncomplete = false })
  end
  local range = {
    start = { line = row - 1, character = context.start },
    ["end"] = { line = row - 1, character = col },
  }
  local items = {}
  for _, item in ipairs(core.items(context)) do
    items[#items + 1] = {
      label = item.label,
      kind = item.kind,
      detail = item.detail,
      filterText = item.filter,
      sortText = item.sort,
      textEdit = { newText = item.insert, range = range },
      data = { path = item.path },
    }
  end
  callback({ items = items, isIncomplete = false })
end

function source:resolve(item, callback)
  local doc = core.documentation(item.data and item.data.path)
  if doc then
    item.documentation = { kind = "markdown", value = doc }
  end
  callback(item)
end

return source
