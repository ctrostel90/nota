local M = {}

function M.available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks.picker ~= nil
end

function M.pick(items, opts, on_choice)
  local entries = vim.tbl_map(function(item)
    return { text = require("notes.pickers").text(item), file = item.path, item = item }
  end, items)
  require("snacks").picker.pick({
    title = opts.prompt,
    items = entries,
    format = "text",
    preview = require("notes.pickers").all_have_paths(items) and "file" or "none",
    -- Keep our order (e.g. most recent first) for ties instead of sorting by length.
    sort = { fields = { "score:desc", "idx" } },
    confirm = function(picker, entry)
      picker:close()
      if entry then
        on_choice(entry.item)
      end
    end,
  })
end

function M.grep(opts)
  require("snacks").picker.grep({ cwd = opts.cwd, title = opts.prompt, glob = "*.md" })
end

return M
