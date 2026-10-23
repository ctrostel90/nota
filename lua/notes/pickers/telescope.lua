local M = {}

function M.available()
  return (pcall(require, "telescope"))
end

--- Wrap a sorter so every space-separated word must match, in any order. Telescope's
--- default (fzy) sorter matches the whole prompt as one ordered sequence, so `#plc #meeting`
--- would miss "standup  #meeting #plc". With fzf-native each word keeps its fzf syntax
--- (`'exact`, `!not`).
local function all_words(base)
  local function words(prompt)
    return vim.split(prompt, "%s+", { trimempty = true })
  end
  return require("telescope.sorters").Sorter:new({
    init = function()
      base:_init()
    end,
    start = function(_, prompt)
      base:_start(prompt)
    end,
    finish = function(_, prompt)
      base:_finish(prompt)
    end,
    destroy = function()
      base:_destroy()
    end,
    scoring_function = function(_, prompt, line, entry)
      local list = words(prompt)
      if #list == 0 then
        return base:scoring_function(prompt, line, entry)
      end
      local total = 0
      for _, word in ipairs(list) do
        local score = base:scoring_function(word, line, entry)
        if score < 0 then
          return -1
        end
        total = total + score
      end
      return total
    end,
    highlighter = base.highlighter and function(_, prompt, display)
      local highlights = {}
      for _, word in ipairs(words(prompt)) do
        vim.list_extend(highlights, base:highlighter(word, display) or {})
      end
      return highlights
    end,
  })
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
          local text = require("notes.pickers").text(item)
          return { value = item, display = text, ordinal = text, path = item.path }
        end,
      }),
      sorter = all_words(conf.generic_sorter({})),
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
