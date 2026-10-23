local config = require("notes.config")
local fs = require("notes.fs")
local templates = require("notes.templates")

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
--- A trailing separator (`work/`) or empty input leaves `stem` nil. `has_folder` is true when
--- the input contained a separator, so `/x` explicitly means the notes root.
function M.parse_name(input)
  input = vim.trim(input or ""):gsub("%.md$", "")
  local folder, name = input:match("^(.*)[/\\](.-)$")
  local has_folder = folder ~= nil
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
    has_folder = has_folder,
    stem = stem ~= "" and stem or nil,
    title = title ~= "" and title or nil,
  }
end

--- Replace `{{key}}`, `{{date:<fmt>}}` and `{{time:<fmt>}}` placeholders from `ctx`.
--- `transform` is applied to substituted values. Unknown keys and `{{cursor}}` become
--- `missing`, or are left in place when `missing` is nil.
local function expand(text, ctx, transform, missing)
  return (text:gsub("{{([%w_]+)(:?)([^{}]*)}}", function(key, colon, fmt)
    local value
    if colon == ":" and (key == "date" or key == "time") then
      value = os.date(fmt)
    elseif colon == "" and fmt == "" and key ~= "cursor" then
      value = ctx[key]
    end
    if value == nil then
      return missing
    end
    value = tostring(value)
    return transform and transform(value) or value
  end))
end

--- Build a note's path relative to its folder (without .md) from a filename pattern.
--- Values are slugified; separators left dangling by empty values and empty segments
--- (including `..`) are dropped. Returns "" when nothing is left.
function M.render_name(pattern, ctx)
  local segments = {}
  for segment in expand(pattern, ctx, M.slugify, ""):gmatch("[^/\\]+") do
    segment = segment:gsub("([-_. ])[-_. ]+", "%1"):gsub("^[-_. ]+", ""):gsub("[-_. ]+$", "")
    if segment ~= "" then
      segments[#segments + 1] = segment
    end
  end
  return table.concat(segments, "/")
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

  local lines = vim.split(expand(template, ctx), "\n", { plain = true })
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

local function find_buf(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and fs.same(name, path) then
      return buf
    end
  end
end

--- A note "exists" if it is on disk or already open as an unsaved buffer.
local function taken(path)
  return fs.exists(path) or find_buf(path) ~= nil
end

local function unique_path(dir, stem)
  local path = fs.join(dir, stem .. ".md")
  local i = 1
  while taken(path) do
    path = fs.join(dir, ("%s-%d.md"):format(stem, i))
    i = i + 1
  end
  return path
end

--- Fill the current (new, unsaved) buffer with `lines`. Nothing is written to disk;
--- the note's folder is created when the user saves.
local function prepare_buffer(lines)
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].fileformat = "unix"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_create_autocmd("BufWritePre", {
    buffer = buf,
    desc = "notes: create note folder on save",
    callback = function(args)
      fs.mkdir_p(vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf)))
    end,
  })
end

function M.open(path, cursor, lines)
  local buf = find_buf(path)
  if buf then
    -- Switch instead of :edit, which would try to reload a modified buffer (E37).
    vim.api.nvim_set_current_buf(buf)
  else
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if lines then
    prepare_buffer(lines)
  end
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

--- Create a note from user input (see `parse_name`) and open it as an unsaved buffer.
--- `opts`: `template` (name, default "default"), `fields` (values for the template's
--- fields), `quiet` (no message when an existing note is opened).
--- The template's `name` pattern picks the filename; if it comes out empty a unique
--- timestamp is used. If the note already exists it is opened unchanged.
--- Returns `path, created`, or `nil, false` for an unknown template.
function M.create(input, opts)
  opts = opts or {}
  local spec, err = templates.get(opts.template or "default")
  if not spec then
    vim.notify("notes: " .. err, vim.log.levels.ERROR)
    return nil, false
  end

  local o = config.options
  local parsed = M.parse_name(input)
  local ctx = vim.tbl_extend("force", opts.fields or {}, {
    title = parsed.title or os.date(o.date_format .. " " .. o.time_format),
    slug = parsed.stem or "",
    date = os.date(o.date_format),
    time = os.date(o.time_format),
  })

  -- A folder typed in the name replaces the template's folder.
  local dirs = parsed.has_folder and parsed.dirs or vim.split(spec.dir, "[/\\]", { trimempty = true })
  local dir = fs.join(config.dir(), unpack(dirs))
  local rel = M.render_name(spec.pattern, ctx)
  local path = rel ~= "" and fs.join(dir, rel .. ".md") or unique_path(dir, os.date(o.timestamp_format))

  if taken(path) then
    M.open(path)
    if not opts.quiet then
      vim.notify("notes: opened existing note " .. path, vim.log.levels.INFO)
    end
    return path, false
  end
  local lines, cursor = M.render(spec.template, ctx)
  M.open(path, cursor, lines)
  return path, true
end

--- Open today's daily note, creating it from the `daily` template if needed.
function M.today()
  return M.new({ template = "daily", name = "", quiet = true })
end

--- All notes as `{ path = absolute, name = relative without .md }`, most recently modified first.
function M.list()
  local root = config.dir()
  local notes = {}
  for _, rel in ipairs(fs.list_files(root, ".md")) do
    local path = fs.join(root, rel)
    notes[#notes + 1] = { path = path, name = rel:sub(1, -4), mtime = fs.mtime(path) }
  end
  table.sort(notes, function(a, b)
    if a.mtime ~= b.mtime then
      return a.mtime > b.mtime
    end
    return a.name < b.name
  end)
  return notes
end

--- Ask each prompt in turn; cancelling any of them aborts without calling `done`.
--- Scheduled between prompts so floating input UIs can close before the next opens.
local function ask(prompts, done, i)
  i = i or 1
  if i > #prompts then
    return done()
  end
  vim.ui.input({ prompt = prompts[i].prompt }, function(input)
    if input == nil then
      return
    end
    prompts[i].answer(input)
    vim.schedule(function()
      ask(prompts, done, i + 1)
    end)
  end)
end

--- Create a note, prompting for whatever is missing.
--- `opts` is a name string or `{ template?, name?, fields?, quiet? }`. A nil `name` and any
--- template fields not in `fields` are prompted for. Without prompts, returns `create`'s result.
function M.new(opts)
  if type(opts) ~= "table" then
    opts = { name = opts }
  end
  local spec, err = templates.get(opts.template or "default")
  if not spec then
    vim.notify("notes: " .. err, vim.log.levels.ERROR)
    return nil, false
  end

  local name, fields = opts.name, vim.deepcopy(opts.fields or {})
  local prompts = {}
  if name == nil then
    local label = spec.name == "default" and "New note" or ("New %s note"):format(spec.name)
    prompts[#prompts + 1] = {
      prompt = label .. " (folder/name, empty = auto): ",
      answer = function(input)
        name = input
      end,
    }
  end
  for _, field in ipairs(spec.fields) do
    if fields[field.name] == nil then
      prompts[#prompts + 1] = {
        prompt = field.prompt,
        answer = function(input)
          fields[field.name] = input
        end,
      }
    end
  end

  local function create()
    return M.create(name, { template = spec.name, fields = fields, quiet = opts.quiet })
  end
  if #prompts == 0 then
    return create()
  end
  ask(prompts, create)
end

--- Command-line completion for :NotesNewFrom: template names first, then folders.
function M.complete_from(arglead, cmdline)
  if cmdline:match("^%s*%S+%s+%S*$") then
    return vim.tbl_filter(function(name)
      return vim.startswith(name, arglead)
    end, templates.names())
  end
  return M.complete(arglead)
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
