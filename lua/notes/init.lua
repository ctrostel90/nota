local M = {}

local function map(lhs, fn, desc)
  if lhs then
    vim.keymap.set("n", lhs, fn, { desc = "Notes: " .. desc })
  end
end

function M.setup(opts)
  local options = require("notes.config").setup(opts)

  local keymaps = options.keymaps
  map(keymaps.new, function()
    M.new()
  end, "new note")
  map(keymaps.today, M.today, "today's note")
  map(keymaps.find, M.find, "find note")
end

--- Create a new note. Prompts for a name when `name` is nil; an empty name uses a timestamp.
function M.new(name)
  return require("notes.note").new(name)
end

--- Open or create today's daily note.
function M.today()
  return require("notes.note").today()
end

--- Pick a note by name and open it.
function M.find()
  local note = require("notes.note")
  local notes = note.list()
  if #notes == 0 then
    vim.notify("notes: no notes in " .. require("notes.config").dir(), vim.log.levels.INFO)
    return
  end
  require("notes.pickers").pick(notes, { prompt = "Find note" }, function(item)
    note.open(item.path)
  end)
end

return M
