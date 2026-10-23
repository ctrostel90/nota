local config = require("notes.config")
local fs = require("notes.fs")
local tags = require("notes.tags")

local M = {}

-- path -> { signature, tags }. Rebuilt per file only when its mtime/size changes, so edits
-- made outside Neovim are picked up too.
local cache = {}
local cache_root

--- Bring the index up to date with the notes dir and return `cache`.
function M.refresh()
  local root = config.dir()
  if root ~= cache_root then
    cache, cache_root = {}, root
  end

  local present = {}
  for _, rel in ipairs(fs.list_files(root, ".md")) do
    local path = fs.join(root, rel)
    present[path] = true
    local signature = fs.signature(path)
    local entry = cache[path]
    if not entry or entry.signature ~= signature then
      local content = fs.read_file(path) or ""
      cache[path] = { signature = signature, name = rel:sub(1, -4), tags = tags.parse(content) }
    end
  end
  for path in pairs(cache) do
    if not present[path] then
      cache[path] = nil
    end
  end
  return cache
end

--- All tags with their notes, including parents of nested tags (`work` for `work/plc`).
--- Returns `{ name, count, paths }[]`, most used first.
function M.tags()
  local by_tag = {}
  for path, entry in pairs(M.refresh()) do
    local seen = {}
    for _, tag in ipairs(entry.tags) do
      for _, name in ipairs(tags.with_parents(tag)) do
        if not seen[name] then
          seen[name] = true
          by_tag[name] = by_tag[name] or { name = name, paths = {} }
          table.insert(by_tag[name].paths, path)
        end
      end
    end
  end

  local result = vim.tbl_values(by_tag)
  for _, tag in ipairs(result) do
    tag.count = #tag.paths
    table.sort(tag.paths)
  end
  table.sort(result, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)
  return result
end

--- Notes with every tag in `include` and none in `exclude` (lowercase, without `#`).
--- Nested tags count for their parents: `include = { "work" }` matches `#work/plc`.
function M.matching(include, exclude)
  local paths = {}
  for path, entry in pairs(M.refresh()) do
    local has = {}
    for _, tag in ipairs(entry.tags) do
      for _, name in ipairs(tags.with_parents(tag)) do
        has[name] = true
      end
    end
    local ok = true
    for _, tag in ipairs(include) do
      ok = ok and has[tag] == true
    end
    for _, tag in ipairs(exclude) do
      ok = ok and not has[tag]
    end
    if ok then
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)
  return paths
end

--- Tags of a single note (as written, without parents).
function M.tags_of(path)
  local entry = M.refresh()[fs.normalize(path)]
  return entry and entry.tags or {}
end

--- Forget everything (e.g. after changing the notes dir in tests).
function M.clear()
  cache, cache_root = {}, nil
end

return M
