-- Dependency-free fallback. Plugins that override vim.ui.select (telescope-ui-select,
-- snacks, fzf-lua's register_ui_select, ...) make this fuzzy too.
local M = {}

function M.available()
  return true
end

function M.pick(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = require("notes.pickers").text,
  }, function(item)
    if item then
      on_choice(item)
    end
  end)
end

--- Prompt for a pattern, run ripgrep once, and show matches in the quickfix list.
function M.grep(opts)
  vim.ui.input({ prompt = opts.prompt .. ": " }, function(pattern)
    if not pattern or pattern == "" then
      return
    end
    local cmd = { "rg", "--vimgrep", "--smart-case", "--path-separator", "/", "--glob", "*.md", "--", pattern, opts.cwd }
    local result = vim.system(cmd, { text = true }):wait()
    -- rg exits 1 for "no matches" and 2 for errors.
    if result.code > 1 then
      vim.notify("notes: rg failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
      return
    end
    local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
    if #lines == 0 then
      vim.notify("notes: no matches for " .. pattern, vim.log.levels.INFO)
      return
    end
    -- %f accepts a leading drive letter (C:/...) on Windows.
    vim.fn.setqflist({}, " ", { title = opts.prompt .. ": " .. pattern, lines = lines, efm = "%f:%l:%c:%m" })
    vim.cmd.copen()
  end)
end

return M
