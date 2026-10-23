-- Shared completion logic for the blink.cmp, nvim-cmp and omnifunc adapters.
local config = require("notes.config")
local fs = require("notes.fs")

local M = {}

local Kind = vim.lsp.protocol.CompletionItemKind

--- Whether `buf` is a note (a markdown file inside the notes dir).
function M.enabled(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.endswith(name:lower(), ".md") and fs.is_inside(name, config.dir())
end

--- What is being completed at byte column `col` (0-based) of `line` (row `row`, 1-based,
--- in `buf`), or nil. Returns `{ kind = "tag"|"link", start, prefix, closed }` where
--- `start` is the 0-based byte column the replaced text starts at (just after `#` / `[[`)
--- and `closed` says whether `]]` already follows the cursor.
function M.context(buf, row, col, line)
  local before = line:sub(1, col)
  -- Inside inline code (odd number of backticks before the cursor) or a fenced block.
  if select(2, before:gsub("`", "")) % 2 == 1 then
    return nil
  end
  if line ~= "" then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
    lines[row] = line
    if require("notes.markdown").prose(lines)[row] == "" then
      return nil
    end
  end

  local link = before:match("%[%[([^%[%]|#]*)$")
  if link then
    return { kind = "link", start = col - #link, prefix = link, closed = line:sub(col + 1, col + 2) == "]]" }
  end
  local tag = before:match("^#([%w_/%-\128-\255]*)$") or before:match("%s#([%w_/%-\128-\255]*)$")
  if tag then
    return { kind = "tag", start = col - #tag, prefix = tag }
  end
end

--- Shortest link target that still resolves to just this note: the filename when it is
--- unique, otherwise as many trailing folders as needed.
local function link_target(name, resolve)
  local segments = vim.split(name, "/", { plain = true })
  for i = #segments, 1, -1 do
    local candidate = table.concat(segments, "/", i)
    if #resolve(candidate) == 1 then
      return candidate
    end
  end
  return name
end

--- Candidates for `ctx` (from `context`). Each item:
--- `{ label, insert, filter, detail, kind, sort, path? }`. Not filtered by the prefix;
--- the completion engine does that (omnifunc filters with matchfuzzy).
function M.items(ctx)
  local items = {}
  if ctx.kind == "tag" then
    for i, tag in ipairs(require("notes.index").tags()) do
      items[#items + 1] = {
        label = "#" .. tag.name,
        insert = tag.name,
        filter = tag.name,
        detail = tag.count == 1 and "1 note" or (tag.count .. " notes"),
        kind = Kind.Keyword,
        sort = ("%05d"):format(i),
      }
    end
    return items
  end

  local notes = require("notes.note").list()
  local resolve = require("notes.links").resolver(notes)
  local cache = require("notes.index").refresh()
  for i, n in ipairs(notes) do
    local title = cache[n.path] and cache[n.path].title
    items[#items + 1] = {
      label = n.name,
      insert = link_target(n.name, resolve) .. (ctx.closed and "" or "]]"),
      filter = title and (n.name .. " " .. title) or n.name,
      detail = title,
      kind = Kind.File,
      sort = ("%05d"):format(i),
      path = n.path,
    }
  end
  return items
end

--- Engines filter on the word before the cursor, so for a multi-word link prefix
--- (`[[Sprint Re`) they would only see "Re". Narrow by every word of the prefix (any order)
--- before handing items over; single-word prefixes are left to the engine.
function M.prefilter(items, ctx)
  if ctx.kind ~= "link" or not ctx.prefix:find("%s") or vim.trim(ctx.prefix) == "" then
    return items
  end
  return vim.fn.matchfuzzy(items, vim.trim(ctx.prefix), { key = "filter" })
end

--- Markdown preview of a note for the documentation window (first lines of the file).
function M.documentation(path, max_lines)
  if not path then
    return nil
  end
  local lines = vim.split(fs.read_file(path) or "", "\r?\n")
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return table.concat(lines, "\n", 1, math.min(#lines, max_lines or 20))
end

return M
