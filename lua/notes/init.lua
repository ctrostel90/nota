local M = {}

function M.setup(opts)
  local options = require("notes.config").setup(opts)

  local keymaps = options.keymaps
  if keymaps.new then
    vim.keymap.set("n", keymaps.new, function()
      M.new()
    end, { desc = "Notes: new note" })
  end
end

--- Create a new note. Prompts for a name when `name` is nil; an empty name uses a timestamp.
function M.new(name)
  return require("notes.note").new(name)
end

return M
