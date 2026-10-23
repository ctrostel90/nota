-- Dependency-free fallback. Plugins that override vim.ui.select (telescope-ui-select,
-- snacks, fzf-lua's register_ui_select, ...) make this fuzzy too.
local M = {}

function M.available()
  return true
end

function M.pick(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = function(item)
      return item.name
    end,
  }, function(item)
    if item then
      on_choice(item)
    end
  end)
end

return M
