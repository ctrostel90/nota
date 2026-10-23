local M = {}

function M.available()
  return (pcall(require, "telescope"))
end

function M.pick(items, opts, on_choice)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")

  pickers
    .new({}, {
      prompt_title = opts.prompt,
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return { value = item, display = item.name, ordinal = item.name, path = item.path }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = require("notes.pickers").all_have_paths(items) and conf.file_previewer({}) or nil,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            on_choice(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

function M.grep(opts)
  require("telescope.builtin").live_grep({ cwd = opts.cwd, prompt_title = opts.prompt, glob_pattern = "*.md" })
end

return M
