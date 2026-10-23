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
  map(keymaps.backlinks, M.backlinks, "backlinks")

  -- Follow-link keys on notes, including ones already open.
  local links = require("notes.links")
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("notes_links", { clear = true }),
    pattern = "markdown",
    callback = function(args)
      links.attach(args.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
      links.attach(buf)
    end
  end
end

--- Follow the [[link]] under the cursor. Returns false when the cursor is not on a link.
function M.follow_link()
  return require("notes.links").follow()
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

--- Open a picker over notes (all of them, or only `paths`), newest first. With
--- `find_tags`, each entry shows the note's tags so the fuzzy query can match them.
local function pick_notes(prompt, paths)
  local note = require("notes.note")
  local notes = note.list()
  if paths then
    local wanted = {}
    for _, path in ipairs(paths) do
      wanted[path] = true
    end
    notes = vim.tbl_filter(function(n)
      return wanted[n.path]
    end, notes)
  end

  if require("notes.config").options.find_tags then
    local cache = require("notes.index").refresh()
    local width = 0
    for _, n in ipairs(notes) do
      n.tags = cache[n.path] and cache[n.path].tags or {}
      if #n.tags > 0 then
        width = math.max(width, vim.fn.strdisplaywidth(n.name))
      end
    end
    width = math.min(width, 40)
    for _, n in ipairs(notes) do
      if #n.tags > 0 then
        local pad = math.max(width - vim.fn.strdisplaywidth(n.name), 0) + 2
        n.display = n.name .. (" "):rep(pad) .. "#" .. table.concat(n.tags, " #")
      end
    end
  end

  require("notes.pickers").pick(notes, { prompt = prompt }, function(item)
    note.open(item.path)
  end)
end

--- Pick a note and open it. Tags are part of each entry, so `#meeting #plc` narrows the
--- list to notes with both.
function M.find()
  if #require("notes.note").list() == 0 then
    vim.notify("notes: no notes in " .. require("notes.config").dir(), vim.log.levels.INFO)
    return
  end
  pick_notes("Find note")
end

--- Split a tag query (`"meeting #plc -draft"` or a list of words) into include/exclude lists.
function M.parse_tag_query(query)
  local words = type(query) == "table" and query or vim.split(query, "%s+", { trimempty = true })
  local include, exclude = {}, {}
  for _, word in ipairs(words) do
    local negate, tag = word:match("^(%-?)#?(.*)$")
    tag = tag:lower()
    if tag ~= "" then
      table.insert(negate == "-" and exclude or include, tag)
    end
  end
  return include, exclude
end

--- Pick a tag, then a note with that tag (nested tags included: `work` matches `#work/plc`).
--- With `query` (`"meeting plc -draft"` or a list of words), skip the tag picker and list
--- notes with every given tag and none of the `-` ones.
function M.tags(query)
  local index = require("notes.index")
  if query and query ~= "" and not (type(query) == "table" and #query == 0) then
    local include, exclude = M.parse_tag_query(query)
    local label = table.concat(
      vim.list_extend(
        vim.tbl_map(function(t)
          return "#" .. t
        end, include),
        vim.tbl_map(function(t)
          return "-#" .. t
        end, exclude)
      ),
      " "
    )
    local paths = index.matching(include, exclude)
    if #paths == 0 then
      vim.notify("notes: no notes match " .. label, vim.log.levels.INFO)
      return
    end
    return pick_notes(label, paths)
  end

  local tags = index.tags()
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
      pick_notes("#" .. item.tag.name, item.tag.paths)
    end)
  end)
end

--- Pick from the notes that link to the current note (or `path`).
function M.backlinks(path)
  local fs = require("notes.fs")
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" or not fs.is_inside(path, require("notes.config").dir()) then
    vim.notify("notes: not a note", vim.log.levels.INFO)
    return
  end
  path = fs.normalize(path)
  local name = vim.fn.fnamemodify(path, ":t:r")
  local paths = require("notes.links").backlinks(path)
  if #paths == 0 then
    vim.notify("notes: no backlinks to " .. name, vim.log.levels.INFO)
    return
  end
  pick_notes("Backlinks: " .. name, paths)
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
