-- Run with: nvim --headless --clean -l tests/run.lua
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2))))
vim.opt.rtp:prepend(root)

local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stdout:write(("FAIL %s\n  %s\n"):format(name, err))
  end
end

local function eq(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local config = require("notes.config")
local fs = require("notes.fs")
local note = require("notes.note")

-- slugify ---------------------------------------------------------------

test("slugify: spaces and case", function()
  eq(note.slugify("  Meeting   Notes "), "meeting-notes")
end)

test("slugify: strips characters Windows rejects", function()
  eq(note.slugify('a:b*c?"d<e>f|g'), "abcdefg")
end)

test("slugify: reserved Windows names", function()
  eq(note.slugify("CON"), "con-note")
  eq(note.slugify("lpt1"), "lpt1-note")
end)

test("slugify: no leading/trailing dots", function()
  eq(note.slugify("..hidden."), "hidden")
  eq(note.slugify(".."), "")
end)

test("slugify: keeps non-ASCII text", function()
  eq(note.slugify("Größe Übersicht"), "größe-Übersicht")
end)

-- parse_name ------------------------------------------------------------

test("parse_name: folder and title", function()
  eq(note.parse_name("work/Meeting Notes"), { dirs = { "work" }, stem = "meeting-notes", title = "Meeting Notes" })
end)

test("parse_name: backslashes and .md suffix", function()
  eq(note.parse_name("Work\\Sub\\x.md"), { dirs = { "work", "sub" }, stem = "x", title = "x" })
end)

test("parse_name: trailing separator means timestamp in folder", function()
  eq(note.parse_name("work/"), { dirs = { "work" } })
end)

test("parse_name: empty input", function()
  eq(note.parse_name(""), { dirs = {} })
  eq(note.parse_name(nil), { dirs = {} })
end)

test("parse_name: cannot escape the notes dir", function()
  eq(note.parse_name("../../etc/passwd").dirs, { "etc" })
end)

-- render ----------------------------------------------------------------

test("render: placeholders and cursor", function()
  local lines, cursor = note.render("# {{title}}\n{{date}}\n\n{{cursor}}", { title = "T", date = "D" })
  eq(lines, { "# T", "D", "", "" })
  eq(cursor, { 4, 0 })
end)

test("render: cursor mid-line, unknown placeholders kept, % is literal", function()
  local lines, cursor = note.render("x {{cursor}}y {{nope}} {{title}}", { title = "100%" })
  eq(lines, { "x y {{nope}} 100%" })
  eq(cursor, { 1, 2 })
end)

test("render: function and list templates", function()
  eq(note.render(function(ctx) return { "# " .. ctx.title } end, { title = "F" }), { "# F" })
end)

test("render: template file with CRLF", function()
  local path = vim.fn.tempname() .. ".md"
  fs.write_file(path, "# {{title}}\r\n\r\n{{cursor}}")
  local lines, cursor = note.render(path, { title = "File" })
  eq(lines, { "# File", "", "" })
  eq(cursor, { 3, 0 })
end)

-- fs --------------------------------------------------------------------

test("fs.is_inside", function()
  eq(fs.is_inside("/a/notes/x.md", "/a/notes"), true)
  eq(fs.is_inside("/a/notes", "/a/notes/"), true)
  eq(fs.is_inside("/a/notes-old/x.md", "/a/notes"), false)
  if fs.is_windows then
    eq(fs.is_inside("c:\\A\\Notes\\x.md", "C:/a/notes"), true)
    eq(fs.same("c:\\A\\x.md", "C:/a/X.md"), true)
  end
end)

test("fs.normalize expands ~", function()
  eq(fs.normalize("~/notes"), vim.fs.normalize(vim.fs.joinpath(vim.uv.os_homedir(), "notes")))
end)

-- create ----------------------------------------------------------------

local tmp = vim.fs.normalize(vim.fn.tempname())
config.setup({ dir = tmp, start_insert = false })

test("create: opens an unsaved buffer, nothing on disk", function()
  local path, created = note.create("work/Hello World")
  eq(created, true)
  eq(path, tmp .. "/work/hello-world.md")
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), path)
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "# Hello World", "", "" })
  eq(vim.api.nvim_win_get_cursor(0), { 3, 0 })
  eq(vim.bo.modified, true)
  eq(fs.exists(path), false)
  eq(fs.exists(tmp .. "/work"), false)
end)

test("create: saving creates the folder and writes LF", function()
  local path = tmp .. "/work/hello-world.md"
  vim.cmd.write()
  eq(fs.read_file(path), "# Hello World\n\n\n")
end)

test("create: existing note is opened, not overwritten", function()
  local path = tmp .. "/work/existing.md"
  fs.write_file(path, "keep me\n")
  local got, created = note.create("work/Existing")
  eq(got, path)
  eq(created, false)
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "keep me" })
  eq(vim.bo.modified, false)
end)

test("create: unsaved note with same name is reused", function()
  local path = note.create("Draft")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })
  local got, created = note.create("draft")
  eq(got, path)
  eq(created, false)
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "edited" })
end)

test("create: empty name uses unique timestamps", function()
  local a = note.create("")
  local b = note.create("")
  assert(a ~= b, "timestamp paths should differ")
  assert(vim.fs.basename(a):match("^%d+%-%d+"), a)
  eq(vim.fs.dirname(a), tmp)
end)

test("complete: lists folders", function()
  eq(note.complete("w"), { "work/" })
end)

-- today -----------------------------------------------------------------

test("today: unsaved daily note from daily template, reused on second call", function()
  local path, created = note.today()
  local date = os.date("%Y-%m-%d")
  eq(path, tmp .. "/daily/" .. date .. ".md")
  eq(created, true)
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "# " .. date, "", "" })
  eq(fs.exists(path), false)
  local again, created_again = note.today()
  eq(again, path)
  eq(created_again, false)
end)

vim.fn.delete(tmp, "rf")

-- list / find -----------------------------------------------------------

local tmp2 = vim.fs.normalize(vim.fn.tempname())
config.setup({ dir = tmp2, start_insert = false })
vim.fn.mkdir(tmp2 .. "/work", "p")
vim.fn.mkdir(tmp2 .. "/.git", "p")
for rel, mtime in pairs({ ["old.md"] = 1000, ["work/new.md"] = 3000, ["mid.md"] = 2000, [".git/x.md"] = 4000 }) do
  fs.write_file(tmp2 .. "/" .. rel, "x\n")
  vim.uv.fs_utime(tmp2 .. "/" .. rel, mtime, mtime)
end
fs.write_file(tmp2 .. "/readme.txt", "x\n")

test("list: markdown only, hidden dirs skipped, newest first", function()
  local names = vim.tbl_map(function(n)
    return n.name
  end, note.list())
  eq(names, { "work/new", "mid", "old" })
  eq(note.list()[1].path, tmp2 .. "/work/new.md")
end)

test("find: picked note is opened", function()
  local original = vim.ui.select
  local shown
  vim.ui.select = function(items, opts, on_choice)
    shown = vim.tbl_map(opts.format_item, items)
    on_choice(items[2])
  end
  require("notes").find()
  vim.ui.select = original
  eq(shown, { "work/new", "mid", "old" })
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp2 .. "/mid.md")
end)

test("pickers: unavailable backend falls back to select with one warning", function()
  local original, warnings = vim.notify, 0
  vim.notify = function(_, level)
    if level == vim.log.levels.WARN then
      warnings = warnings + 1
    end
  end
  config.setup({ dir = tmp2, picker = "telescope" })
  local pickers = require("notes.pickers")
  local a, b = pickers.backend(), pickers.backend()
  vim.notify = original
  eq(a, require("notes.pickers.select"))
  eq(b, a)
  eq(warnings, 1)
end)

test("config: rejects unknown picker", function()
  local ok, err = pcall(config.setup, { picker = "bogus" })
  eq(ok, false)
  assert(tostring(err):find("picker"), err)
end)

vim.fn.delete(tmp2, "rf")

io.stdout:write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
