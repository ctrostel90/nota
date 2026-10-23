local M = {}

M.defaults = {
  -- Root directory for notes. `~` and environment variables are expanded.
  dir = "~/notes",
  -- Templates by name. Each is content (a string, a path to a template file, or a
  -- function(ctx) returning a string or list of lines) or a spec table:
  --   { template = <content>, dir = "folder", name = "{{date:%Y-%m-%d}}-{{slug}}",
  --     fields = { { name = "customer", prompt = "Customer: " } } }
  -- Placeholders: {{title}}, {{slug}}, {{date}}, {{time}}, {{date:<strftime>}}, fields, {{cursor}}.
  -- Your entries are merged per template with these built-ins, not replaced wholesale.
  templates = {
    default = "# {{title}}\n\n{{cursor}}",
    daily = { template = "# {{date}}\n\n{{cursor}}", dir = "daily", name = "{{date:%Y-%m-%d}}" },
  },
  -- Optional folder of template files; each `<name>.md` becomes template `<name>`.
  template_dir = nil,
  date_format = "%Y-%m-%d",
  time_format = "%H:%M",
  -- Filename used when a new note's name pattern comes out empty.
  timestamp_format = "%Y%m%d-%H%M%S",
  -- "auto" picks the first installed of telescope, fzf-lua, snacks; falls back to vim.ui.select.
  picker = "auto",
  -- Enter insert mode at {{cursor}} after creating a note.
  start_insert = true,
  -- Set a key to false to disable that mapping.
  keymaps = {
    new = "<leader>nn",
    today = "<leader>nd",
    find = "<leader>nf",
  },
}

M.pickers = { "auto", "telescope", "fzf-lua", "snacks", "select" }

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  vim.validate("opts", opts, "table", true)
  opts = opts or {}
  local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- Only the user's own entries; notes.templates layers them over the built-ins so that
  -- e.g. `daily = "..."` changes the content but keeps the built-in folder and name.
  options.templates = vim.deepcopy(opts.templates or {})

  vim.validate("dir", options.dir, "string")
  vim.validate("templates", options.templates, "table")
  for name, entry in pairs(options.templates) do
    require("notes.templates").validate(name, entry)
  end
  vim.validate("template_dir", options.template_dir, "string", true)
  vim.validate("date_format", options.date_format, "string")
  vim.validate("time_format", options.time_format, "string")
  vim.validate("timestamp_format", options.timestamp_format, "string")
  vim.validate("picker", options.picker, function(v)
    return vim.list_contains(M.pickers, v)
  end, "one of " .. table.concat(M.pickers, ", "))
  vim.validate("start_insert", options.start_insert, "boolean")
  for name, lhs in pairs(options.keymaps) do
    vim.validate("keymaps." .. name, lhs, { "string", "boolean" })
  end

  M.options = options
  return options
end

--- Absolute, normalized notes directory.
function M.dir()
  return require("notes.fs").normalize(M.options.dir)
end

return M
