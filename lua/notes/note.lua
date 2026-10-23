local config = require("notes.config")
local fs = require("notes.fs")

local M = {}

-- Names Windows refuses as filenames regardless of extension.
local RESERVED = { con = true, prn = true, aux = true, nul = true }
for i = 1, 9 do
  RESERVED["com" .. i] = true
  RESERVED["lpt" .. i] = true
end

--- Turn arbitrary text into a filename-safe slug that works on Windows and Linux.
function M.slugify(text)
  local slug = vim.trim(text):lower()
  slug = slug:gsub('[%c<>:"/\\|?*#%[%]]', "")
  slug = slug:gsub("%s+", "-"):gsub("%-%-+", "-")
  -- No leading dots (hidden files, `..`) and no trailing dots/dashes (Windows strips trailing dots).
  slug = slug:gsub("^[-.]+", ""):gsub("[-.]+$", "")
  if RESERVED[slug] then
    slug = slug .. "-note"
  end
  return slug
end

--- Split user input like `work/Meeting Notes` into folders, a filename stem and a title.
--- A trailing separator (`work/`) or empty input leaves `stem` nil so a timestamp is used.
function M.parse_name(input)
  input = vim.trim(input or ""):gsub("%.md$", "")
  local folder, name = input:match("^(.*)[/\\](.-)$")
  if not folder then
    folder, name = "", input
  end

  local dirs = {}
  for segment in folder:gmatch("[^/\\]+") do
    local slug = M.slugify(segment)
    if slug ~= "" then
      dirs[#dirs + 1] = slug
    end
  end

  local title = vim.trim(name)
  local stem = M.slugify(title)
  return {
    dirs = dirs,
    stem = stem ~= "" and stem or nil,
    title = title ~= "" and title or nil,
  }
end

--- Render a template into lines. Returns `lines, cursor` where cursor is a {row, col}
--- position (1-based row, 0-based col) of the first {{cursor}} marker, or nil.
function M.render(template, ctx)
  if type(template) == "function" then
    template = template(ctx)
  end
  if type(template) == "table" then
    template = table.concat(template, "\n")
  end
  if not template:find("\n") and vim.fn.filereadable(fs.normalize(template)) == 1 then
    template = assert(fs.read_file(fs.normalize(template)))
  end
  template = template:gsub("\r\n", "\n")

  -- Unknown placeholders and {{cursor}} are left in place.
  local text = template:gsub("{{(%w+)}}", function(key)
    if key ~= "cursor" and ctx[key] ~= nil then
      return tostring(ctx[key])
    end
  end)

  local lines = vim.split(text, "\n", { plain = true })
  local cursor
  for i, line in ipairs(lines) do
    local col = line:find("{{cursor}}", 1, true)
    if col then
      cursor = cursor or { i, col - 1 }
      lines[i] = line:gsub("{{cursor}}", "")
    end
  end
  return lines, cursor
end

local function unique_path(dir, stem)
  local path = fs.join(dir, stem .. ".md")
  local i = 1
  while fs.exists(path) do
    path = fs.join(dir, ("%s-%d.md"):format(stem, i))
    i = i + 1
  end
  return path
end

function M.open(path, cursor)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if not cursor then
    return
  end
  vim.api.nvim_win_set_cursor(0, cursor)
  if config.options.start_insert then
    local line = vim.api.nvim_get_current_line()
    if cursor[2] >= #line then
      vim.cmd.startinsert({ bang = true })
    else
      vim.cmd.startinsert()
    end
  end
end

--- Create a note from user input (see `parse_name`) and open it.
--- If the note already exists it is opened unchanged. Returns `path, created`.
function M.create(input)
  local opts = config.options
  local parsed = M.parse_name(input)
  local dir = fs.join(config.dir(), unpack(parsed.dirs))

  local path, title
  if parsed.stem then
    path, title = fs.join(dir, parsed.stem .. ".md"), parsed.title
  else
    path = unique_path(dir, os.date(opts.timestamp_format))
    title = os.date(opts.date_format .. " " .. opts.time_format)
  end

  if fs.exists(path) then
    M.open(path)
    vim.notify("notes: opened existing note " .. path, vim.log.levels.INFO)
    return path, false
  end

  local lines, cursor = M.render(opts.templates.default, {
    title = title,
    date = os.date(opts.date_format),
    time = os.date(opts.time_format),
  })
  fs.mkdir_p(dir)
  local ok, err = fs.write_file(path, table.concat(lines, "\n") .. "\n")
  if not ok then
    vim.notify("notes: could not create " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return nil, false
  end
  M.open(path, cursor)
  return path, true
end

--- Create a note named `name`, or prompt for one when `name` is nil.
function M.new(name)
  if name then
    return M.create(name)
  end
  vim.ui.input({ prompt = "New note (folder/name, empty = timestamp): " }, function(input)
    if input then
      M.create(input)
    end
  end)
end

--- Command-line completion: existing folders inside the notes dir.
function M.complete(arglead)
  local matches = {}
  for _, dir in ipairs(fs.list_dirs(config.dir())) do
    local candidate = dir .. "/"
    if vim.startswith(candidate, arglead) then
      matches[#matches + 1] = candidate
    end
  end
  return matches
end

return M
