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

--- Whether `path` is `dir` or somewhere below it. Case-insensitive on Windows.
function M.is_inside(path, dir)
  path, dir = M.normalize(path), M.normalize(dir)
  if M.is_windows then
    path, dir = path:lower(), dir:lower()
  end
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

--- Subdirectories of `root` as relative paths (`work`, `work/meetings`), skipping hidden ones.
function M.list_dirs(root, depth)
  local dirs = {}
  if vim.fn.isdirectory(root) == 0 then
    return dirs
  end
  local function visible(name)
    return not name:match("^%.") and not name:match("/%.")
  end
  for name, type in vim.fs.dir(root, { depth = depth or 5, skip = visible }) do
    if type == "directory" and visible(name) then
      dirs[#dirs + 1] = name
    end
  end
  table.sort(dirs)
  return dirs
end

return M
