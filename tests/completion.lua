-- Integration tests for the completion sources against the real engines.
-- Run one engine per process:
--   NOTES_TEST_PLUGINS="<dir>" nvim --headless --clean -l tests/completion.lua blink|cmp
-- NOTES_TEST_PLUGINS is a ;-separated list of plugin directories (blink.cmp or nvim-cmp).
--
-- Completion engines react to typing through the event loop, so the keys are sent to a
-- child Neovim over RPC (nvim_input) and its state is queried between steps.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2))))
local engine = arg[1]
local passed, failed = 0, 0

local function eq(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

-- child Neovim ----------------------------------------------------------

local address = vim.fn.has("win32") == 1 and ([[\\.\pipe\notes-test-%d]]):format(vim.uv.os_getpid())
  or (vim.fn.tempname() .. ".sock")
local job = vim.fn.jobstart({ vim.v.progpath, "--headless", "--clean", "--listen", address }, vim.empty_dict())
local chan
vim.wait(5000, function()
  local ok, c = pcall(vim.fn.sockconnect, "pipe", address, { rpc = true })
  chan = ok and c or nil
  return chan ~= nil and chan > 0
end, 50)
assert(chan and chan > 0, "could not connect to child nvim")

--- Run Lua in the child; `...` is available as the chunk's varargs.
local function child(code, ...)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
end

local function input(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
end

--- Type text one character at a time, like a person. Sending it in one nvim_input
--- batches it into a single TextChangedI, which nvim-cmp does not autocomplete on.
local function type_text(text)
  for _, char in ipairs(vim.fn.split(text, [[\zs]])) do
    input(char == "<" and "<lt>" or char)
    vim.wait(30)
  end
end

local function wait_for(what, code, ms)
  local ok = vim.wait(ms or 5000, function()
    return child(code) == true
  end, 30)
  if not ok then
    error("timed out waiting for " .. what, 2)
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stdout:write(("FAIL %s: %s\n  %s\n"):format(engine, name, err))
  end
  input("<Esc><Esc>")
  vim.wait(50)
end

local plugins = vim.split(os.getenv("NOTES_TEST_PLUGINS") or "", ";", { trimempty = true })
local tmp = vim.fs.normalize(vim.fn.tempname())
child(
  [[
  local root, tmp, plugins = ...
  vim.opt.rtp:prepend(root)
  for _, dir in ipairs(plugins) do
    vim.opt.rtp:prepend(dir)
    -- Added after startup, so source plugin/ files like a plugin manager would.
    for _, file in ipairs(vim.fn.glob(dir .. "/plugin/*.{lua,vim}", false, true)) do
      vim.cmd.source(vim.fn.fnameescape(file))
    end
  end
  vim.cmd("filetype on")
  vim.o.columns, vim.o.lines = 200, 50
  local fs = require("notes.fs")
  vim.fn.mkdir(tmp .. "/work", "p")
  fs.write_file(tmp .. "/work/sprint.md", "# Sprint Review\n#meeting #work/plc\n")
  fs.write_file(tmp .. "/größe.md", "# Größe\n#meeting\n")
  require("notes").setup({ dir = tmp, start_insert = false })
]],
  root,
  tmp,
  plugins
)

-- engines ---------------------------------------------------------------

local engines = {
  blink = {
    setup = [[
      require("blink.cmp").setup({
        fuzzy = { implementation = "lua" },
        sources = {
          default = { "notes" },
          providers = { notes = { name = "Notes", module = "notes.completion.blink" } },
        },
        completion = { documentation = { auto_show = false } },
      })
    ]],
    visible = [[return require("blink.cmp").is_menu_visible()]],
    labels = [[return vim.tbl_map(function(i) return i.label end, require("blink.cmp.completion.list").items)]],
  },
  cmp = {
    setup = [[
      local cmp = require("cmp")
      require("notes").setup({ dir = require("notes.config").options.dir, start_insert = false })
      cmp.setup({
        sources = { { name = "notes" } },
        mapping = { ["<C-y>"] = cmp.mapping.confirm({ select = true }) },
        performance = { debounce = 0, throttle = 0 },
      })
    ]],
    visible = [[return require("cmp").visible()]],
    labels = [[return vim.tbl_map(function(e) return e:get_completion_item().label end, require("cmp").get_entries())]],
  },
}

-- Built-in omnifunc: no plugin, the menu is opened explicitly with <C-x><C-o>.
engines.omni = {
  -- With the default 'completeopt' a single match is inserted without showing the menu.
  setup = [[vim.o.completeopt = "menuone"]],
  trigger = "<C-x><C-o>",
  visible = [[return vim.fn.pumvisible() == 1]],
  labels = [[return vim.tbl_map(function(i) return i.abbr end, vim.fn.complete_info({ "items" }).items)]],
}

local driver = assert(engines[engine], "unknown engine " .. tostring(engine))
child(driver.setup)

local function labels()
  return child(driver.labels)
end

--- Open a fresh buffer for `path` containing `line`, then type `keys` at its end.
local function type_at_end(path, line, keys)
  child(
    [[
    local path, line = ...
    vim.cmd("enew!")
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  ]],
    path,
    line
  )
  input("A")
  type_text(keys)
  if driver.trigger then
    input(driver.trigger)
  end
end

local function type_in_note(line, keys)
  type_at_end(tmp .. "/scratch.md", line, keys)
end

local function accept_and_expect(line)
  input("<C-y>")
  local ok = vim.wait(3000, function()
    return child("return vim.api.nvim_get_current_line()") == line
  end, 30)
  if not ok then
    error(("expected line %q, got %q"):format(line, child("return vim.api.nvim_get_current_line()")), 2)
  end
end

-- tests -----------------------------------------------------------------

test("tag completion inserts the tag", function()
  type_in_note("see ", "#wor")
  wait_for("menu", driver.visible)
  eq(labels(), { "#work", "#work/plc" })
  accept_and_expect("see #work")
end)

test("nested tag completion replaces the whole prefix", function()
  type_in_note("", "#work/p")
  wait_for("menu", driver.visible)
  eq(labels()[1], "#work/plc")
  accept_and_expect("#work/plc")
end)

test("link completion by title closes the brackets", function()
  type_in_note("see ", "[[Sprint Re")
  wait_for("menu", driver.visible)
  -- Engines filter on the word before the cursor ("Re"), so other notes may also match;
  -- the title match must rank first.
  eq(labels()[1], "work/sprint")
  accept_and_expect("see [[sprint]]")
end)

test("link completion after non-ASCII text", function()
  type_in_note("ä ö ü ", "[[grö")
  wait_for("menu", driver.visible)
  accept_and_expect("ä ö ü [[größe]]")
end)

test("no menu outside the notes dir", function()
  type_at_end(vim.fn.tempname() .. ".md", "", "#wor")
  vim.wait(500)
  eq(child(driver.visible), false)
end)

pcall(vim.rpcrequest, chan, "nvim_command", "qa!")
vim.fn.jobstop(job)
vim.fn.delete(tmp, "rf")
io.stdout:write(("\n%s: %d passed, %d failed\n"):format(engine, passed, failed))
os.exit(failed > 0 and 1 or 0)
