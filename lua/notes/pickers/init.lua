local config = require("notes.config")

local M = {}

-- Backends in auto-detect order. Each is a module `notes.pickers.<name>` exposing:
--   available() -> boolean
--   pick(items, opts, on_choice)  -- items: { name, path? }[], opts: { prompt }, on_choice(item)
--   grep(opts)                    -- opts: { cwd, prompt }; searches *.md below cwd
M.order = { "telescope", "fzf_lua", "snacks", "select" }

local aliases = { ["fzf-lua"] = "fzf_lua" }
local warned = {}

local function load(name)
  local ok, backend = pcall(require, "notes.pickers." .. name)
  if ok and backend.available() then
    return backend
  end
end

function M.backend()
  local wanted = config.options.picker
  if wanted ~= "auto" then
    local backend = load(aliases[wanted] or wanted)
    if backend then
      return backend
    end
    if not warned[wanted] then
      warned[wanted] = true
      vim.notify(("notes: picker %q is not available, falling back"):format(wanted), vim.log.levels.WARN)
    end
  end
  for _, name in ipairs(M.order) do
    local backend = load(name)
    if backend then
      return backend
    end
  end
end

--- Previews are only shown when every item is a file.
function M.all_have_paths(items)
  for _, item in ipairs(items) do
    if not item.path then
      return false
    end
  end
  return #items > 0
end

function M.pick(items, opts, on_choice)
  M.backend().pick(items, opts, on_choice)
end

function M.grep(opts)
  M.backend().grep(opts)
end

return M
