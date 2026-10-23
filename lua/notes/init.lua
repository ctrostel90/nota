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
  map(keymaps.grep, M.grep, "grep notes")
end

--- Create a new note. `opts` is a name string or `{ template?, name?, fields? }`;
--- a missing name and missing template fields are prompted for. An empty name uses
--- the template's name pattern, falling back to a timestamp.
---   require("notes").new({ template = "customer" })
function M.new(opts)
  return require("notes.note").new(opts)
end

--- Create a note from `template`, or pick a template first when it is nil.
function M.new_from(template, name)
  if template then
    return M.new({ template = template, name = name })
  end
  local templates = require("notes.templates")
  local items = vim.tbl_map(function(t)
    return { name = t, path = templates.get(t).path }
  end, templates.names())
  require("notes.pickers").pick(items, { prompt = "Template" }, function(item)
    -- Let the picker close before the name prompt opens.
    vim.schedule(function()
      M.new({ template = item.name, name = name })
    end)
  end)
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

--- Search the contents of all notes (requires ripgrep).
function M.grep()
  local dir = require("notes.config").dir()
  if vim.fn.executable("rg") == 0 then
    vim.notify("notes: :NotesGrep needs ripgrep (rg) on your PATH", vim.log.levels.ERROR)
    return
  end
  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("notes: no notes in " .. dir, vim.log.levels.INFO)
    return
  end
  require("notes.pickers").grep({ cwd = dir, prompt = "Grep notes" })
end

return M
