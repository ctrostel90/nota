-- Integration tests for picker backends against the real plugins.
-- Run one backend per process:
--   NOTES_TEST_PLUGINS="<dir>;<dir>" nvim --headless --clean -l tests/pickers.lua telescope|fzf_lua|snacks
-- NOTES_TEST_PLUGINS is a ;-separated list of plugin directories to add to 'runtimepath'
-- (e.g. telescope.nvim + plenary.nvim, fzf-lua, snacks.nvim).
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2))))
vim.opt.rtp:prepend(root)
for dir in (os.getenv("NOTES_TEST_PLUGINS") or ""):gmatch("[^;]+") do
  vim.opt.rtp:prepend(dir)
end

local backend_name = arg[1]
local passed, failed = 0, 0

-- Pickers hide their preview in small windows (telescope's cutoff is 120 columns).
vim.o.columns, vim.o.lines = 200, 50

--- Close leftover picker windows so one failure does not cascade into the next test.
local function cleanup()
  vim.cmd.stopinsert()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd("enew!")
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stdout:write(("FAIL %s: %s\n  %s\n"):format(backend_name, name, err))
  end
  cleanup()
end

local function eq(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function wait_for(what, cond, ms)
  if not vim.wait(ms or 5000, cond, 20) then
    error("timed out waiting for " .. what, 2)
  end
end

local fs = require("notes.fs")
local tmp = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(tmp .. "/work", "p")
local files = { ["work/new.md"] = "new content\nhas a needle\n", ["mid.md"] = "mid content\n", ["old.md"] = "old content\n" }
for rel, content in pairs(files) do
  fs.write_file(tmp .. "/" .. rel, content)
end
local items = {
  { name = "work/new", path = tmp .. "/work/new.md" },
  { name = "mid", path = tmp .. "/mid.md" },
  { name = "old", path = tmp .. "/old.md" },
}

require("notes.config").setup({ dir = tmp, picker = backend_name == "fzf_lua" and "fzf-lua" or backend_name })
local pickers = require("notes.pickers")
local backend = pickers.backend()

local function current_file()
  return vim.fs.normalize(vim.api.nvim_buf_get_name(0))
end

-- Each driver opens the picker filtered to `query`, waits for it, and confirms the match.
local drivers = {}

drivers.telescope = {
  setup = function()
    require("telescope").setup({})
  end,
  pick = function(query, open)
    local action_state = require("telescope.actions.state")
    open()
    wait_for("telescope prompt", function()
      return vim.bo.filetype == "TelescopePrompt"
    end)
    local bufnr = vim.api.nvim_get_current_buf()
    local picker = action_state.get_current_picker(bufnr)
    picker:set_prompt(query)
    wait_for("telescope results", function()
      return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
    end)
    return picker, function()
      require("telescope.actions").select_default(bufnr)
    end
  end,
  preview_lines = function(picker)
    local buf = picker.previewer and picker.previewer.state and picker.previewer.state.bufnr
    return buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or {}
  end,
  grep = function(query)
    -- live_grep takes default_text; pass it through by wrapping the builtin.
    local builtin = require("telescope.builtin")
    local live_grep = builtin.live_grep
    builtin.live_grep = function(o)
      o.default_text = query
      return live_grep(o)
    end
    require("notes").grep()
    builtin.live_grep = live_grep
    local action_state = require("telescope.actions.state")
    wait_for("telescope grep prompt", function()
      return vim.bo.filetype == "TelescopePrompt"
    end)
    local bufnr = vim.api.nvim_get_current_buf()
    -- Ask this picker, not get_selected_entry(), which can still hold the previous picker's entry.
    local picker = action_state.get_current_picker(bufnr)
    wait_for("telescope grep results", function()
      return picker.manager and picker.manager:num_results() >= 1 and picker:get_selection() ~= nil
    end)
    require("telescope.actions").select_default(bufnr)
  end,
}

drivers.fzf_lua = {
  setup = function()
    require("fzf-lua").setup({})
  end,
  -- fzf-lua feeds Lua lists to fzf through FZF_DEFAULT_COMMAND, which fzf ignores when its
  -- stdin is not a terminal (as in headless runs). So the real fzf_exec is started, then
  -- the selection is simulated by closing the window and calling the "enter" action the
  -- way fzf-lua does after fzf exits.
  pick = function(query, open)
    local fzf = require("fzf-lua")
    local fzf_exec, captured, contents = fzf.fzf_exec, nil, nil
    fzf.fzf_exec = function(c, o)
      contents, captured = c, o
      return fzf_exec(c, o)
    end
    open()
    fzf.fzf_exec = fzf_exec
    wait_for("fzf window", function()
      return vim.bo.filetype == "fzf"
    end)
    return captured, function()
      require("fzf-lua.win").__SELF():close()
      local entry = vim.tbl_filter(function(c)
        return c:find(query, 1, true) ~= nil
      end, contents)
      assert(#entry == 1, "query should match one entry: " .. vim.inspect(entry))
      -- fzf-lua normalizes actions to `{ fn = ... }` tables.
      local action = captured.actions["enter"]
      action = type(action) == "table" and action.fn or action
      action({ entry[1] }, captured)
    end
  end,
  preview_ok = function(captured)
    local cls = captured.previewer._ctor()
    return cls.parse_entry(nil, "mid").path == tmp .. "/mid.md"
  end,
  has_preview = function(captured)
    return captured.previewer ~= nil
  end,
  grep = function(query)
    local fzf = require("fzf-lua")
    local live_grep = fzf.live_grep
    fzf.live_grep = function(o)
      o.query = query
      o.fzf_opts = vim.tbl_extend("force", o.fzf_opts or {}, { ["--select-1"] = true })
      return live_grep(o)
    end
    require("notes").grep()
    fzf.live_grep = live_grep
  end,
}

drivers.snacks = {
  setup = function()
    require("snacks").setup({ picker = { enabled = true } })
  end,
  pick = function(query, open)
    local Snacks = require("snacks")
    local pick = Snacks.picker.pick
    Snacks.picker.pick = function(o)
      o.pattern = query
      return pick(o)
    end
    open()
    Snacks.picker.pick = pick
    local picker
    wait_for("snacks results", function()
      picker = Snacks.picker.get()[1]
      return picker ~= nil and not picker:is_active() and #picker:items() == 1
    end)
    return picker, function()
      picker:action("confirm")
    end
  end,
  preview_lines = function(picker)
    local win = picker.preview and picker.preview.win
    local buf = win and win.buf
    return buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or {}
  end,
  grep = function(query)
    local Snacks = require("snacks")
    local grep = Snacks.picker.grep
    Snacks.picker.grep = function(o)
      o.search = query
      return grep(o)
    end
    require("notes").grep()
    Snacks.picker.grep = grep
    local picker
    wait_for("snacks grep results", function()
      picker = Snacks.picker.get()[1]
      return picker ~= nil and not picker:is_active() and picker:count() >= 1
    end)
    picker:action("confirm")
  end,
}

local driver = drivers[backend_name]
assert(driver, "unknown backend " .. tostring(backend_name))
driver.setup()

test("backend is selected", function()
  eq(backend, require("notes.pickers." .. backend_name))
end)

test("pick: filters, previews and confirms the right item", function()
  local chosen
  local handle, confirm = driver.pick("mid", function()
    pickers.pick(items, { prompt = "Find note" }, function(item)
      chosen = item
    end)
  end)

  wait_for("preview", function()
    if driver.preview_ok then
      return driver.preview_ok(handle)
    end
    return vim.deep_equal(driver.preview_lines(handle), { "mid content" })
  end)
  confirm()
  wait_for("choice", function()
    return chosen ~= nil
  end)
  eq(chosen, items[2])
end)

test("pick: items without paths work (no preview)", function()
  local chosen
  local handle, confirm = driver.pick("internal", function()
    pickers.pick({ { name = "customer" }, { name = "internal" } }, { prompt = "Template" }, function(item)
      chosen = item
    end)
  end)
  if driver.has_preview then
    eq(driver.has_preview(handle), false)
  end
  confirm()
  wait_for("choice", function()
    return chosen ~= nil
  end)
  eq(chosen, { name = "internal" })
end)

test("pick: display text is matched, words in any order", function()
  if backend_name == "fzf_lua" then
    return -- matching happens inside fzf, which these tests cannot drive
  end
  local chosen
  local tagged = {
    { name = "work/new", display = "work/new  #meeting #plc", path = tmp .. "/work/new.md" },
    { name = "mid", display = "mid       #meeting", path = tmp .. "/mid.md" },
    { name = "old", path = tmp .. "/old.md" },
  }
  local _, confirm = driver.pick("#plc #meeting", function()
    pickers.pick(tagged, { prompt = "Find note" }, function(item)
      chosen = item
    end)
  end)
  confirm()
  wait_for("choice", function()
    return chosen ~= nil
  end)
  eq(chosen, tagged[1])
end)

test("NotesFind opens the chosen note", function()
  local _, confirm = driver.pick("old", function()
    require("notes").find()
  end)
  confirm()
  wait_for("note opened", function()
    return current_file() == tmp .. "/old.md"
  end)
end)

test("NotesGrep finds and opens the matching note", function()
  driver.grep("needle")
  local ok = vim.wait(10000, function()
    return current_file() == tmp .. "/work/new.md"
  end, 20)
  assert(ok, "grep match not opened; current file: " .. current_file() .. " ft=" .. vim.bo.filetype)
  eq(vim.api.nvim_win_get_cursor(0)[1], 2)
end)

vim.fn.delete(tmp, "rf")
io.stdout:write(("\n%s: %d passed, %d failed\n"):format(backend_name, passed, failed))
os.exit(failed > 0 and 1 or 0)
