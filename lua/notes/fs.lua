local M = {}

M.is_windows = vim.fn.has("win32") == 1

--- Expand `~`/env vars, make absolute, and use forward slashes on every OS.
function M.normalize(path)
  return vim.fs.normalize(vim.fs.abspath(vim.fs.normalize(path)))
end

function M.join(...)
  return vim.fs.normalize(vim.fs.joinpath(...))
end

function M.exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

function M.mkdir_p(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Normalized form used for comparing paths. Case-insensitive on Windows.
local function comparable(path)
  path = M.normalize(path)
  return M.is_windows and path:lower() or path
end

function M.same(a, b)
  return comparable(a) == comparable(b)
end

--- Whether `path` is `dir` or somewhere below it. Case-insensitive on Windows.
function M.is_inside(path, dir)
  path, dir = comparable(path), comparable(dir)
  dir = dir:gsub("/+$", "")
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

function M.read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Write in binary mode so line endings stay LF on Windows.
function M.write_file(path, content)
  local f, err = io.open(path, "wb")
  if not f then
    return nil, err
  end
  f:write(content)
  f:close()
  return true
end

local function visible(name)
  return not name:match("^%.") and not name:match("/%.")
end

--- Relative paths below `root` (forward slashes), skipping hidden files and folders.
local function walk(root, depth, want)
  local found = {}
  if vim.fn.isdirectory(root) == 0 then
    return found
  end
  for name, type in vim.fs.dir(root, { depth = depth, skip = visible }) do
    if visible(name) and want(name, type) then
      found[#found + 1] = name
    end
  end
  table.sort(found)
  return found
end

--- Subdirectories of `root` as relative paths (`work`, `work/meetings`).
function M.list_dirs(root, depth)
  return walk(root, depth or 5, function(_, type)
    return type == "directory"
  end)
end

--- Files below `root` ending in `ext` as relative paths (`work/meeting.md`).
function M.list_files(root, ext, depth)
  return walk(root, depth or 20, function(name, type)
    return type == "file" and (not ext or vim.endswith(name, ext))
  end)
end

function M.mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec or 0
end

return M
