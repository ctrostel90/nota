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
  eq(
    note.parse_name("work/Meeting Notes"),
    { dirs = { "work" }, has_folder = true, stem = "meeting-notes", title = "Meeting Notes" }
  )
end)

test("parse_name: backslashes and .md suffix", function()
  eq(note.parse_name("Work\\Sub\\x.md"), { dirs = { "work", "sub" }, has_folder = true, stem = "x", title = "x" })
end)

test("parse_name: trailing separator means timestamp in folder", function()
  eq(note.parse_name("work/"), { dirs = { "work" }, has_folder = true })
end)

test("parse_name: empty input", function()
  eq(note.parse_name(""), { dirs = {}, has_folder = false })
  eq(note.parse_name(nil), { dirs = {}, has_folder = false })
end)

test("parse_name: leading separator means the notes root", function()
  eq(note.parse_name("/x"), { dirs = {}, has_folder = true, stem = "x", title = "x" })
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

test("render: {{date:fmt}} and field placeholders", function()
  local lines = note.render("{{date:%Y}} {{customer_name}} {{date}}", { customer_name = "Acme", date = "D" })
  eq(lines, { os.date("%Y") .. " Acme D" })
end)

-- render_name -----------------------------------------------------------

test("render_name: values slugified, dangling separators dropped", function()
  local day = os.date("%Y-%m-%d")
  eq(note.render_name("{{date:%Y-%m-%d}}-{{customer}}-{{slug}}", { customer = "Acme GmbH", slug = "kickoff" }),
    day .. "-acme-gmbh-kickoff")
  eq(note.render_name("{{date:%Y-%m-%d}}-{{customer}}-{{slug}}", { customer = "", slug = "" }), day)
  eq(note.render_name("{{slug}}", { slug = "" }), "")
  eq(note.render_name("{{unknown}}-{{slug}}", { slug = "x" }), "x")
end)

test("render_name: subfolders in pattern, no escaping via ..", function()
  eq(note.render_name("{{date:%Y}}/{{slug}}", { slug = "x" }), os.date("%Y") .. "/x")
  eq(note.render_name("../{{slug}}", { slug = "x" }), "x")
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

test("grep (select backend): rg results land in quickfix", function()
  if vim.fn.executable("rg") == 0 then
    io.stdout:write("SKIP grep: rg not installed\n")
    return
  end
  fs.write_file(tmp2 .. "/work/new.md", "first\nthe Needle line\n")
  fs.write_file(tmp2 .. "/readme.txt", "needle in a txt\n")
  local original = vim.ui.input
  vim.ui.input = function(_, on_confirm)
    on_confirm("needle")
  end
  config.setup({ dir = tmp2, picker = "select" })
  require("notes").grep()
  vim.ui.input = original
  local items = vim.fn.getqflist()
  eq(#items, 1)
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(items[1].bufnr)), tmp2 .. "/work/new.md")
  eq({ items[1].lnum, items[1].col }, { 2, 5 })
  vim.cmd.cclose()
end)

test("config: rejects unknown picker", function()
  local ok, err = pcall(config.setup, { picker = "bogus" })
  eq(ok, false)
  assert(tostring(err):find("picker"), err)
end)

vim.fn.delete(tmp2, "rf")

-- named templates -------------------------------------------------------

local templates = require("notes.templates")
local tmp3 = vim.fs.normalize(vim.fn.tempname())
local tpl_dir = tmp3 .. "/.templates"
vim.fn.mkdir(tpl_dir, "p")
fs.write_file(tpl_dir .. "/customer.md", "# {{title}}\nCustomer: {{customer}}\n\n#meeting #customer\n{{cursor}}")
fs.write_file(tpl_dir .. "/standup.md", "# Standup {{date}}\n{{cursor}}")
config.setup({
  dir = tmp3,
  template_dir = tpl_dir,
  start_insert = false,
  templates = {
    daily = "# Day {{date}}\n{{cursor}}",
    internal = { template = "# {{title}} (internal)\n{{cursor}}", dir = "meetings/internal", name = "{{date:%Y-%m-%d}}-{{slug}}" },
    customer = {
      dir = "meetings/customers",
      name = "{{date:%Y-%m-%d}}-{{customer}}-{{slug}}",
      fields = { { name = "customer", prompt = "Customer: " } },
    },
    folder_only = { dir = "inbox" },
  },
})
local day = os.date("%Y-%m-%d")

local function buf_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

test("templates: names from built-ins, config and template_dir", function()
  eq(templates.names(), { "customer", "daily", "default", "folder_only", "internal", "standup" })
end)

test("templates: unknown name", function()
  local spec, err = templates.get("nope")
  eq(spec, nil)
  assert(err:find("nope"), err)
end)

test("templates: daily content override keeps built-in dir and name", function()
  local spec = templates.get("daily")
  eq({ spec.template, spec.dir, spec.pattern }, { "# Day {{date}}\n{{cursor}}", "daily", "{{date:%Y-%m-%d}}" })
end)

test("templates: content from template_dir, spec from config", function()
  local spec = templates.get("customer")
  eq(spec.path, tpl_dir .. "/customer.md")
  eq(spec.template, tpl_dir .. "/customer.md")
  eq(spec.fields, { { name = "customer", prompt = "Customer: " } })
end)

test("templates: no content anywhere falls back to default content", function()
  eq(templates.get("folder_only").template, "# {{title}}\n\n{{cursor}}")
end)

test("create: customer template with field", function()
  local path, created = note.create("Kickoff", { template = "customer", fields = { customer = "Acme GmbH" } })
  eq(created, true)
  eq(path, tmp3 .. "/meetings/customers/" .. day .. "-acme-gmbh-kickoff.md")
  eq(buf_lines(), { "# Kickoff", "Customer: Acme GmbH", "", "#meeting #customer", "" })
end)

test("create: typed folder overrides template dir, / means root", function()
  eq(note.create("other/Sync", { template = "internal" }), tmp3 .. "/other/" .. day .. "-sync.md")
  eq(note.create("/Sync", { template = "internal" }), tmp3 .. "/" .. day .. "-sync.md")
  eq(buf_lines(), { "# Sync (internal)", "" })
end)

test("create: empty name with dated pattern uses the date", function()
  eq(note.create("", { template = "internal" }), tmp3 .. "/meetings/internal/" .. day .. ".md")
end)

test("create: template-only content via template_dir", function()
  note.create("x", { template = "standup" })
  eq(buf_lines(), { "# Standup " .. day, "" })
end)

test("create: unknown template creates nothing", function()
  local original, errors = vim.notify, 0
  vim.notify = function(_, level)
    errors = errors + (level == vim.log.levels.ERROR and 1 or 0)
  end
  local path = note.create("x", { template = "nope" })
  vim.notify = original
  eq(path, nil)
  eq(errors, 1)
end)

test("today: uses daily template override", function()
  local path = note.today()
  eq(path, tmp3 .. "/daily/" .. day .. ".md")
  eq(buf_lines(), { "# Day " .. day, "" })
end)

local function stub_input(answers)
  local original, asked = vim.ui.input, {}
  vim.ui.input = function(opts, on_confirm)
    asked[#asked + 1] = opts.prompt
    on_confirm(table.remove(answers, 1))
  end
  return asked, function()
    vim.ui.input = original
  end
end

test("new: prompts for name, then fields, in order", function()
  local asked, restore = stub_input({ "Review", "Beckhoff" })
  require("notes").new({ template = "customer" })
  local expected = tmp3 .. "/meetings/customers/" .. day .. "-beckhoff-review.md"
  vim.wait(500, function()
    return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == expected
  end)
  restore()
  eq(asked, { "New customer note (folder/name, empty = auto): ", "Customer: " })
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), expected)
end)

test("new: given fields are not prompted; cancel aborts", function()
  local asked, restore = stub_input({})
  local before = vim.api.nvim_get_current_buf()
  require("notes").new({ template = "customer", fields = { customer = "Acme" } })
  vim.wait(100)
  restore()
  eq(asked, { "New customer note (folder/name, empty = auto): " })
  eq(vim.api.nvim_get_current_buf(), before)
end)

test("new_from: picks template, then prompts", function()
  local original_select = vim.ui.select
  local shown
  vim.ui.select = function(items, opts, on_choice)
    shown = vim.tbl_map(opts.format_item, items)
    on_choice(items[vim.fn.index(shown, "internal") + 1])
  end
  local _, restore = stub_input({ "Planning" })
  require("notes").new_from()
  local expected = tmp3 .. "/meetings/internal/" .. day .. "-planning.md"
  vim.wait(500, function()
    return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == expected
  end)
  restore()
  vim.ui.select = original_select
  eq(shown, templates.names())
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), expected)
end)

test("complete_from: template names, then folders", function()
  eq(note.complete_from("cu", "NotesNewFrom cu"), { "customer" })
  eq(note.complete_from("", "NotesNewFrom "), templates.names())
  eq(note.complete_from("m", "NotesNewFrom customer m"), {})
end)

test("config: rejects bad field names", function()
  local ok, err = pcall(config.setup, { templates = { x = { fields = { "has space" } } } })
  eq(ok, false)
  assert(tostring(err):find("fields"), err)
end)

vim.fn.delete(tmp3, "rf")

-- tags ------------------------------------------------------------------

local tags = require("notes.tags")

test("tags: basic, nested, case-insensitive, unique, in order", function()
  eq(tags.parse("#Meeting notes #plc and #work/PLC-io\nagain #meeting"), { "meeting", "plc", "work/plc-io" })
end)

test("tags: headings, mid-word, anchors and numbers are not tags", function()
  local text = table.concat({
    "# Heading",
    "## Sub #real",
    "C# and page#anchor and [link](#section) and foo#bar",
    "issue #123 but #2026-q4 is a tag",
  }, "\n")
  eq(tags.parse(text), { "real", "2026-q4" })
end)

test("tags: trailing / and - trimmed, non-ASCII kept", function()
  eq(tags.parse("#work/ #draft- #Übersicht #größe"), { "work", "draft", "Übersicht", "größe" })
end)

test("tags: fenced and inline code ignored", function()
  local text = table.concat({
    "before #a",
    "````markdown",
    "-- #notatag",
    "```",
    "still code, shorter fence does not close #nope",
    "````",
    "~~~",
    "#tilde-code",
    "~~~",
    "use `#inline` and ``x #two `y` `` but #b",
  }, "\n")
  eq(tags.parse(text), { "a", "b" })
end)

test("tags: CRLF input", function()
  eq(tags.parse("#a\r\n#b\r\n"), { "a", "b" })
end)

test("tags.with_parents", function()
  eq(tags.with_parents("work/plc/io"), { "work", "work/plc", "work/plc/io" })
end)

-- index / NotesTags -----------------------------------------------------

local index = require("notes.index")
local tmp4 = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(tmp4 .. "/work", "p")
vim.fn.mkdir(tmp4 .. "/.templates", "p")
fs.write_file(tmp4 .. "/a.md", "#work/plc #meeting\n")
fs.write_file(tmp4 .. "/work/b.md", "#work\n")
fs.write_file(tmp4 .. "/c.md", "#meeting #Customer\n")
fs.write_file(tmp4 .. "/.templates/t.md", "#template-only\n")
config.setup({ dir = tmp4, start_insert = false, picker = "select" })
index.clear()

local function summary()
  return vim.tbl_map(function(t)
    return { t.name, t.count }
  end, index.tags())
end

test("index: counts include nested parents, hidden dirs skipped", function()
  eq(summary(), { { "meeting", 2 }, { "work", 2 }, { "customer", 1 }, { "work/plc", 1 } })
  eq(index.tags()[2].paths, { tmp4 .. "/a.md", tmp4 .. "/work/b.md" })
  eq(index.tags_of(tmp4 .. "/c.md"), { "meeting", "customer" })
end)

test("index: picks up edits, new and deleted files", function()
  fs.write_file(tmp4 .. "/c.md", "#customer only, longer now\n")
  fs.write_file(tmp4 .. "/d.md", "#new\n")
  vim.fn.delete(tmp4 .. "/work/b.md")
  eq(summary(), { { "customer", 1 }, { "meeting", 1 }, { "new", 1 }, { "work", 1 }, { "work/plc", 1 } })
end)

test("NotesTags: pick tag, then note", function()
  local original = vim.ui.select
  local prompts, shown = {}, {}
  vim.ui.select = function(items, opts, on_choice)
    prompts[#prompts + 1] = opts.prompt
    shown[#shown + 1] = vim.tbl_map(opts.format_item, items)
    on_choice(items[#prompts == 1 and 4 or 1])
  end
  require("notes").tags()
  vim.wait(500, function()
    return #prompts == 2
  end)
  vim.ui.select = original
  eq(prompts, { "Tags", "#work" })
  eq(shown[1][4], "#work (1)")
  eq(shown[2], { "a" })
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp4 .. "/a.md")
end)

test("NotesTags with argument and unknown tag", function()
  local original_select, original_notify = vim.ui.select, vim.notify
  local shown, notified
  vim.ui.select = function(items, opts)
    shown = vim.tbl_map(opts.format_item, items)
  end
  vim.notify = function(msg)
    notified = msg
  end
  require("notes").tags("#Customer")
  require("notes").tags("missing")
  vim.ui.select, vim.notify = original_select, original_notify
  eq(shown, { "c" })
  assert(notified:find("#missing"), notified)
end)

vim.fn.delete(tmp4, "rf")

io.stdout:write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
