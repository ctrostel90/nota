-- blink.cmp source. Add to your blink.cmp config:
--   sources = {
--     default = { "lsp", "path", "snippets", "notes" },
--     providers = { notes = { name = "Notes", module = "notes.completion.blink" } },
--   }
-- It only activates in notes (markdown files inside the notes dir).
local core = require("notes.completion.core")

local source = {}

function source.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = source })
end

function source:enabled()
  return core.enabled(vim.api.nvim_get_current_buf())
end

function source:get_trigger_characters()
  return { "#", "[" }
end

function source:get_completions(ctx, callback)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local context = core.context(ctx.bufnr, row, col, ctx.line)
  local items = {}
  if context then
    -- Non-LSP sources use byte offsets, matching the cursor column.
    local range = {
      start = { line = row - 1, character = context.start },
      ["end"] = { line = row - 1, character = col },
    }
    for _, item in ipairs(core.prefilter(core.items(context), context)) do
      items[#items + 1] = {
        label = item.label,
        kind = item.kind,
        detail = item.detail,
        filterText = item.filter,
        sortText = item.sort,
        textEdit = { newText = item.insert, range = range },
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        data = { path = item.path },
      }
    end
  end
  -- Ask again as the user types: multi-word link prefixes are pre-filtered here.
  callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
end

function source:resolve(item, callback)
  item = vim.deepcopy(item)
  local doc = core.documentation(item.data and item.data.path)
  if doc then
    item.documentation = { kind = "markdown", value = doc }
  end
  callback(item)
end

return source
