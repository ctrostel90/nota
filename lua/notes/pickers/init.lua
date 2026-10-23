local config = require("notes.config")

local M = {}

-- Backends in auto-detect order. Each is a module `notes.pickers.<name>` exposing:
--   available() -> boolean
--   pick(items, opts, on_choice)  -- items: { path, name }[], opts: { prompt }, on_choice(item)
-- TODO(milestone 3): add telescope, fzf_lua, snacks ahead of select.
M.order = { "select" }

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

function M.pick(items, opts, on_choice)
  M.backend().pick(items, opts, on_choice)
end

return M
