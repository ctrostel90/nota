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
  map(keymaps.tags, function()
    M.tags()
  end, "notes by tag")
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

local function pick_notes(paths, prompt)
  local note = require("notes.note")
  local wanted = {}
  for _, path in ipairs(paths) do
    wanted[path] = true
  end
  local notes = vim.tbl_filter(function(n)
    return wanted[n.path]
  end, note.list())
  require("notes.pickers").pick(notes, { prompt = prompt }, function(item)
    note.open(item.path)
  end)
end

--- Pick a tag, then a note with that tag (nested tags included: `work` matches `#work/plc`).
--- With `tag`, skip straight to its notes.
function M.tags(tag)
  local tags = require("notes.index").tags()
  if tag then
    tag = tag:gsub("^#", ""):lower()
    for _, t in ipairs(tags) do
      if t.name == tag then
        return pick_notes(t.paths, "#" .. tag)
      end
    end
    vim.notify("notes: no notes tagged #" .. tag, vim.log.levels.INFO)
    return
  end
  if #tags == 0 then
    vim.notify("notes: no tags found in " .. require("notes.config").dir(), vim.log.levels.INFO)
    return
  end
  local items = vim.tbl_map(function(t)
    return { name = ("#%s (%d)"):format(t.name, t.count), tag = t }
  end, tags)
  require("notes.pickers").pick(items, { prompt = "Tags" }, function(item)
    -- Let the tag picker close before the note picker opens.
    vim.schedule(function()
      pick_notes(item.tag.paths, "#" .. item.tag.name)
    end)
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
