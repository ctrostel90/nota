local M = {}

M.defaults = {
  -- Root directory for notes. `~` and environment variables are expanded.
  dir = "~/notes",
  -- Templates: a string, a path to a template file, or a function(ctx) returning a string or list of lines.
  -- Placeholders: {{title}}, {{date}}, {{time}}, {{cursor}}.
  templates = {
    default = "# {{title}}\n\n{{cursor}}",
  },
  date_format = "%Y-%m-%d",
  time_format = "%H:%M",
  -- Filename used when a new note is created without a name.
  timestamp_format = "%Y%m%d-%H%M%S",
  -- Enter insert mode at {{cursor}} after creating a note.
  start_insert = true,
  -- Set a key to false to disable that mapping.
  keymaps = {
    new = "<leader>nn",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  vim.validate("opts", opts, "table", true)
  local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

  vim.validate("dir", options.dir, "string")
  vim.validate("templates.default", options.templates.default, { "string", "function", "table" })
  vim.validate("date_format", options.date_format, "string")
  vim.validate("time_format", options.time_format, "string")
  vim.validate("timestamp_format", options.timestamp_format, "string")
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
