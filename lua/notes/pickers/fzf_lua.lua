local M = {}

function M.available()
  return (pcall(require, "fzf-lua"))
end

function M.pick(items, opts, on_choice)
  local utils = require("fzf-lua.utils")
  local text = require("notes.pickers").text
  local by_text, names = {}, {}
  for _, item in ipairs(items) do
    by_text[text(item)] = item
    names[#names + 1] = text(item)
  end
  local function lookup(entry)
    return entry and by_text[utils.strip_ansi_coloring(entry)]
  end

  local previewer
  if require("notes.pickers").all_have_paths(items) then
    -- Entries are display text, not paths, so map them back for the builtin previewer.
    previewer = {
      _ctor = function()
        local cls = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
        function cls:parse_entry(entry)
          return { path = lookup(entry).path, line = 1, col = 1 }
        end
        return cls
      end,
    }
  end

  require("fzf-lua").fzf_exec(names, {
    prompt = opts.prompt .. "> ",
    previewer = previewer,
    actions = {
      ["enter"] = function(selected)
        local item = lookup(selected[1])
        if item then
          on_choice(item)
        end
      end,
    },
  })
end

function M.grep(opts)
  local defaults = require("fzf-lua.defaults").defaults.grep.rg_opts
  require("fzf-lua").live_grep({
    cwd = opts.cwd,
    prompt = opts.prompt .. "> ",
    -- Default rg_opts end with `-e`; keep that last so the query follows it.
    rg_opts = defaults:gsub("%s*%-e$", "") .. ' -g "*.md" -e',
  })
end

return M
