-- Run every test suite, fetching test-only plugins first:
--   nvim -l tests/all.lua            all suites
--   nvim -l tests/all.lua pickers    only suites whose name contains "pickers"
-- Plugins are cloned (lua/, plugin/, autoload/ only) into .tests/plugins, or
-- $NOTES_TEST_DEPS, pinned to the refs below.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2))))
local deps_dir = vim.fs.normalize(os.getenv("NOTES_TEST_DEPS") or (root .. "/.tests/plugins"))
local filter = arg[1]

local deps = {
  ["plenary.nvim"] = { "https://github.com/nvim-lua/plenary.nvim", "74b06c6c75e4eeb3108ec01852001636d85a932b" },
  ["telescope.nvim"] = { "https://github.com/nvim-telescope/telescope.nvim", "9377230aa5305d9e9aca4ed8dadf1070fb4aa9fc" },
  ["fzf-lua"] = { "https://github.com/ibhagwan/fzf-lua", "5dca84e" },
  ["snacks.nvim"] = { "https://github.com/folke/snacks.nvim", "882c996" },
  ["blink.cmp"] = { "https://github.com/saghen/blink.cmp", "v1.10.2" },
  ["nvim-cmp"] = { "https://github.com/hrsh7th/nvim-cmp", "2ffe79f" },
}

local suites = {
  { name = "unit", file = "tests/run.lua" },
  { name = "pickers:telescope", file = "tests/pickers.lua", arg = "telescope", deps = { "telescope.nvim", "plenary.nvim" }, needs = { "rg" } },
  { name = "pickers:fzf_lua", file = "tests/pickers.lua", arg = "fzf_lua", deps = { "fzf-lua" }, needs = { "rg", "fzf" } },
  { name = "pickers:snacks", file = "tests/pickers.lua", arg = "snacks", deps = { "snacks.nvim" }, needs = { "rg" } },
  { name = "completion:blink", file = "tests/completion.lua", arg = "blink", deps = { "blink.cmp" } },
  { name = "completion:cmp", file = "tests/completion.lua", arg = "cmp", deps = { "nvim-cmp" } },
  { name = "completion:omni", file = "tests/completion.lua", arg = "omni" },
}

local function git(args, cwd)
  local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  return result.code == 0, vim.trim((result.stdout or "") .. (result.stderr or ""))
end

--- Clone `name` if needed and check out its pinned ref. Only code directories are checked
--- out (some plugins ship test files whose names are too long for Windows).
local function ensure(name)
  local url, ref = unpack(deps[name])
  local dir = deps_dir .. "/" .. name
  if vim.fn.isdirectory(dir .. "/.git") == 0 then
    vim.fn.mkdir(deps_dir, "p")
    io.stdout:write(("fetching %s@%s\n"):format(name, ref))
    local ok, out = git({ "clone", "-q", "--filter=blob:none", "--no-checkout", url, dir })
    assert(ok, out)
    assert(git({ "sparse-checkout", "set", "lua", "plugin", "autoload" }, dir))
  end
  local wanted_ok, wanted = git({ "rev-parse", ref .. "^{commit}" }, dir)
  if not wanted_ok then
    -- Shallow or older clone: fetch the ref first.
    git({ "fetch", "-q", "--filter=blob:none", "origin", ref }, dir)
    git({ "fetch", "-q", "--tags", "--filter=blob:none", "origin" }, dir)
    wanted_ok, wanted = git({ "rev-parse", ref .. "^{commit}" }, dir)
    assert(wanted_ok, ("cannot resolve %s@%s: %s"):format(name, ref, wanted))
  end
  -- Always check out: a fresh --no-checkout clone has HEAD set but no files yet.
  local ok, out = git({ "checkout", "-q", wanted }, dir)
  assert(ok, out)
  return dir
end

local results, failed = {}, false
for _, suite in ipairs(suites) do
  local first = #results + 1
  if not filter or suite.name:find(filter, 1, true) then
    local missing = vim.tbl_filter(function(exe)
      return vim.fn.executable(exe) == 0
    end, suite.needs or {})
    if #missing > 0 then
      results[#results + 1] = ("SKIP %-20s needs %s"):format(suite.name, table.concat(missing, ", "))
    else
      local dirs = vim.tbl_map(ensure, suite.deps or {})
      local cmd = { vim.v.progpath, "--headless", "--clean", "-l", suite.file, suite.arg }
      local result = vim
        .system(cmd, { cwd = root, text = true, timeout = 300000, env = { NOTES_TEST_PLUGINS = table.concat(dirs, ";") } })
        :wait()
      local output = ((result.stdout or "") .. (result.stderr or "")):gsub("\r", "")
      local summary = output:match("(%d+ passed, %d+ failed)") or ("exit code " .. result.code)
      local ok = result.code == 0
      failed = failed or not ok
      results[#results + 1] = ("%s %-20s %s"):format(ok and "PASS" or "FAIL", suite.name, summary)
      if not ok then
        for line in output:gmatch("[^\n]+") do
          if line:match("^FAIL") or line:match("^  ") or line:match("rror") then
            results[#results + 1] = "    " .. line
          end
        end
      end
    end
    io.stdout:write(table.concat(results, "\n", first), "\n")
  end
end

io.stdout:write(failed and "\nSome suites failed.\n" or "\nAll suites passed.\n")
os.exit(failed and 1 or 0)
