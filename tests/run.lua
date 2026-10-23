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
  eq(shown[2], { "a  #work/plc #meeting" })
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
  eq(shown, { "c  #customer" })
  assert(notified:find("#missing"), notified)
end)

-- multiple tags ---------------------------------------------------------

fs.write_file(tmp4 .. "/e.md", "#meeting #plc #draft\n")
fs.write_file(tmp4 .. "/f.md", "#meeting #plc\n")
fs.write_file(tmp4 .. "/long-note-name.md", "#meeting\n")

local function capture_select(fn)
  local original, shown, prompt = vim.ui.select, nil, nil
  vim.ui.select = function(items, opts)
    shown = vim.tbl_map(opts.format_item, items)
    prompt = opts.prompt
  end
  fn()
  vim.ui.select = original
  return shown, prompt
end

test("parse_tag_query: words, # optional, - excludes, case-insensitive", function()
  local include, exclude = require("notes").parse_tag_query("Meeting #plc -draft -#Old")
  eq({ include, exclude }, { { "meeting", "plc" }, { "draft", "old" } })
  eq({ require("notes").parse_tag_query({ "a", "-b" }) }, { { "a" }, { "b" } })
end)

test("index.matching: all included, none excluded, parents count", function()
  local names = function(paths)
    return vim.tbl_map(function(p)
      return vim.fs.basename(p)
    end, paths)
  end
  eq(names(index.matching({ "meeting", "plc" }, {})), { "e.md", "f.md" })
  eq(names(index.matching({ "meeting", "plc" }, { "draft" })), { "f.md" })
  eq(names(index.matching({ "work" }, {})), { "a.md" })
  eq(#index.matching({}, { "meeting" }), #note.list() - 4)
end)

test("NotesTags with several tags and an exclusion", function()
  local shown, prompt = capture_select(function()
    require("notes").tags({ "meeting", "plc", "-draft" })
  end)
  eq(prompt, "#meeting #plc -#draft")
  eq(shown, { "f  #meeting #plc" })
end)

test("NotesFind shows aligned tags, untagged notes stay bare", function()
  fs.write_file(tmp4 .. "/untagged.md", "nothing here\n")
  local shown = capture_select(function()
    require("notes").find()
  end)
  assert(vim.list_contains(shown, "untagged"), vim.inspect(shown))
  assert(vim.list_contains(shown, "f               #meeting #plc"), vim.inspect(shown))
  assert(vim.list_contains(shown, "long-note-name  #meeting"), vim.inspect(shown))
end)

test("find_tags = false shows plain names", function()
  config.setup({ dir = tmp4, start_insert = false, picker = "select", find_tags = false })
  local shown = capture_select(function()
    require("notes").find()
  end)
  assert(vim.list_contains(shown, "f"), vim.inspect(shown))
  config.setup({ dir = tmp4, start_insert = false, picker = "select" })
end)

test("NotesTags completion: each word, - prefix kept", function()
  vim.cmd.runtime("plugin/notes.lua")
  eq(vim.fn.getcompletion("NotesTags meeting pl", "cmdline"), { "plc" })
  eq(vim.fn.getcompletion("NotesTags -dr", "cmdline"), { "-draft" })
  eq(vim.fn.getcompletion("NotesTags #cust", "cmdline"), { "customer" })
end)

vim.fn.delete(tmp4, "rf")

-- links -----------------------------------------------------------------

local links = require("notes.links")

test("links.parse: targets, aliases, headings; skips code, embeds, same-note", function()
  local text = table.concat({
    "See [[a]] and [[b|Alias]] and [[ c #Heading ]] and [[a]] again",
    "![[image.png]] [[doc.pdf]] [[#local]] [[notes.md]] `[[inline]]`",
    "```",
    "[[fenced]]",
    "```",
  }, "\n")
  eq(links.parse(text), { "a", "b", "c", "notes.md" })
end)

test("links.link_at: only when the cursor is inside the brackets", function()
  local line = "x [[one|alias]] y [[two#H]]"
  eq(links.link_at(line, 0), nil)
  eq(links.link_at(line, 2), { target = "one" })
  eq(links.link_at(line, 14), { target = "one" })
  eq(links.link_at(line, 15), nil)
  eq(links.link_at(line, 20), { target = "two", heading = "H" })
end)

test("links.resolver: exact, slugified, suffix, ambiguous, rooted", function()
  local notes = {
    { name = "work/meeting" },
    { name = "personal/meeting" },
    { name = "meeting-notes" },
    { name = "2026/standup" },
  }
  local resolve = links.resolver(notes)
  local function names(target)
    return vim.tbl_map(function(n)
      return n.name
    end, resolve(target))
  end
  eq(names("Meeting Notes"), { "meeting-notes" })
  eq(names("meeting"), { "work/meeting", "personal/meeting" })
  eq(names("Work\\Meeting.md"), { "work/meeting" })
  eq(names("standup"), { "2026/standup" })
  eq(names("/meeting"), {})
  eq(names("/work/meeting"), { "work/meeting" })
  eq(names("nope"), {})
end)

local tmp5 = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(tmp5 .. "/work", "p")
vim.fn.mkdir(tmp5 .. "/personal", "p")
fs.write_file(tmp5 .. "/index.md", "See [[work/meeting#Agenda]] and [[meeting]] and [[New Idea]].\nplain text\n")
fs.write_file(tmp5 .. "/work/meeting.md", "# Meeting\n\n## Agenda\nitems\n")
fs.write_file(tmp5 .. "/personal/meeting.md", "# Personal\nback to [[index]]\n")
fs.write_file(tmp5 .. "/other.md", "`[[index]]` is code, but [[Index|home]] is not\n")
config.setup({ dir = tmp5, start_insert = false, picker = "select" })

local function on_link(text)
  vim.cmd.edit(vim.fn.fnameescape(tmp5 .. "/index.md"))
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  vim.api.nvim_win_set_cursor(0, { 1, line:find(text, 1, true) + 1 })
end

test("follow: single match opens the note at the heading", function()
  on_link("[[work/meeting#Agenda]]")
  eq(require("notes").follow_link(), true)
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp5 .. "/work/meeting.md")
  eq(vim.api.nvim_win_get_cursor(0)[1], 3)
end)

test("follow: several matches open a picker", function()
  on_link("[[meeting]]")
  local original, shown = vim.ui.select, nil
  vim.ui.select = function(items, opts, on_choice)
    shown = vim.tbl_map(opts.format_item, items)
    on_choice(items[vim.fn.index(shown, "personal/meeting") + 1])
  end
  links.follow()
  vim.ui.select = original
  table.sort(shown)
  eq(shown, { "personal/meeting", "work/meeting" })
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp5 .. "/personal/meeting.md")
end)

test("follow: missing note is created (unsaved) after confirming", function()
  local original = vim.fn.confirm
  vim.fn.confirm = function()
    return 2
  end
  on_link("[[New Idea]]")
  links.follow()
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp5 .. "/index.md")

  vim.fn.confirm = function()
    return 1
  end
  links.follow()
  vim.fn.confirm = original
  eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), tmp5 .. "/new-idea.md")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false), { "# New Idea" })
  eq(fs.exists(tmp5 .. "/new-idea.md"), false)
end)

test("follow: off a link returns false", function()
  vim.cmd.edit(vim.fn.fnameescape(tmp5 .. "/index.md"))
  vim.api.nvim_win_set_cursor(0, { 2, 2 })
  eq(links.follow(), false)
end)

test("backlinks: resolved links only, code ignored, ambiguous counts", function()
  local function names(path)
    return vim.tbl_map(function(p)
      return p:sub(#tmp5 + 2)
    end, links.backlinks(path))
  end
  eq(names(tmp5 .. "/index.md"), { "other.md", "personal/meeting.md" })
  eq(names(tmp5 .. "/work/meeting.md"), { "index.md" })
  eq(names(tmp5 .. "/personal/meeting.md"), { "index.md" })
  eq(names(tmp5 .. "/other.md"), {})
end)

test("NotesBacklinks: picker for the current note", function()
  vim.cmd.edit(vim.fn.fnameescape(tmp5 .. "/index.md"))
  local shown, prompt = capture_select(function()
    require("notes").backlinks()
  end)
  eq(prompt, "Backlinks: index")
  table.sort(shown)
  eq(shown, { "other", "personal/meeting" })
end)

test("attach: follow keys only in buffers inside the notes dir", function()
  require("notes").setup({ dir = tmp5, start_insert = false, picker = "select" })
  vim.cmd.edit(vim.fn.fnameescape(tmp5 .. "/other.md"))
  links.attach(0)
  eq(vim.fn.maparg("<CR>", "n", false, true).buffer, 1)
  eq(vim.fn.maparg("gf", "n", false, true).buffer, 1)
  local outside = vim.fn.tempname() .. ".md"
  vim.cmd.edit(vim.fn.fnameescape(outside))
  links.attach(0)
  eq(vim.fn.maparg("<CR>", "n", false, true), {})
end)

vim.fn.delete(tmp5, "rf")

-- completion ------------------------------------------------------------

local core = require("notes.completion.core")
local tmp6 = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(tmp6 .. "/work", "p")
vim.fn.mkdir(tmp6 .. "/personal", "p")
fs.write_file(tmp6 .. "/work/meeting.md", "# Sprint Review\n#work #meeting\n")
fs.write_file(tmp6 .. "/personal/meeting.md", "#meeting\n")
fs.write_file(tmp6 .. "/ideas.md", "no heading, #idea")
vim.uv.fs_utime(tmp6 .. "/work/meeting.md", 3000, 3000)
vim.uv.fs_utime(tmp6 .. "/personal/meeting.md", 2000, 2000)
vim.uv.fs_utime(tmp6 .. "/ideas.md", 1000, 1000)
config.setup({ dir = tmp6, start_insert = false, picker = "select" })

local function ctx_at(line)
  -- `@` marks the cursor.
  local col = line:find("@", 1, true) - 1
  line = line:gsub("@", "", 1)
  return core.context(0, 1, col, line)
end

test("completion.context: tags", function()
  vim.cmd.enew()
  eq(ctx_at("#wo@"), { kind = "tag", start = 1, prefix = "wo" })
  eq(ctx_at("text #work/pl@ more"), { kind = "tag", start = 6, prefix = "work/pl" })
  eq(ctx_at("x #@"), { kind = "tag", start = 3, prefix = "" })
  eq(ctx_at("C#@"), nil)
  eq(ctx_at("page#an@"), nil)
  eq(ctx_at("`#co@"), nil)
  eq(ctx_at("`a` #ok@"), { kind = "tag", start = 5, prefix = "ok" })
end)

test("completion.context: links", function()
  eq(ctx_at("see [[Meet No@"), { kind = "link", start = 6, prefix = "Meet No", closed = false })
  eq(ctx_at("[[@]]"), { kind = "link", start = 2, prefix = "", closed = true })
  eq(ctx_at("[[a|b@"), nil)
  eq(ctx_at("[[a#He@"), nil)
  eq(ctx_at("[[done]] @"), nil)
end)

test("completion.context: nothing inside fenced code", function()
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "```", "#ta", "```", "#ta" })
  eq(core.context(0, 2, 3, "#ta"), nil)
  eq(core.context(0, 4, 3, "#ta"), { kind = "tag", start = 1, prefix = "ta" })
end)

test("completion.items: tags by use, with counts", function()
  local items = core.items({ kind = "tag" })
  eq(vim.tbl_map(function(i)
    return { i.label, i.insert, i.detail }
  end, items), { { "#meeting", "meeting", "2 notes" }, { "#idea", "idea", "1 note" }, { "#work", "work", "1 note" } })
end)

test("completion.items: links insert the shortest unique target", function()
  local items = core.items({ kind = "link", closed = false })
  eq(vim.tbl_map(function(i)
    return { i.label, i.insert, i.detail }
  end, items), {
    { "work/meeting", "work/meeting]]", "Sprint Review" },
    { "personal/meeting", "personal/meeting]]", nil },
    { "ideas", "ideas]]", nil },
  })
  eq(items[1].filter, "work/meeting Sprint Review")
  eq(core.items({ kind = "link", closed = true })[3].insert, "ideas")
end)

test("completion.documentation: first lines", function()
  eq(core.documentation(tmp6 .. "/work/meeting.md"), "# Sprint Review\n#work #meeting")
  eq(core.documentation(tmp6 .. "/work/meeting.md", 1), "# Sprint Review")
end)

test("completion.enabled: notes only", function()
  vim.cmd.edit(vim.fn.fnameescape(tmp6 .. "/ideas.md"))
  eq(core.enabled(0), true)
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".md"))
  eq(core.enabled(0), false)
end)

test("omnifunc: start column, fuzzy filtering, set on notes", function()
  local omni = require("notes.completion.omni")
  vim.cmd.edit(vim.fn.fnameescape(tmp6 .. "/ideas.md"))
  omni.attach(0)
  eq(vim.bo.omnifunc, "v:lua.require'notes.completion.omni'.complete")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "see [[spr" })
  vim.api.nvim_win_set_cursor(0, { 1, 9 })
  eq(omni.complete(1, ""), 6)
  eq(vim.tbl_map(function(i)
    return i.word
  end, omni.complete(0, "spr")), { "work/meeting]]" })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plain" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  eq(omni.complete(1, ""), -3)
end)

vim.fn.delete(tmp6, "rf")

io.stdout:write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
