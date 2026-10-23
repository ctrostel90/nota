local config = require("notes.config")
local fs = require("notes.fs")

local M = {}

--- Split the inside of `[[...]]` into target and heading: `work/x#Heading|alias`.
local function parse_inner(inner)
  inner = inner:gsub("|.*$", "")
  local target, heading = inner:match("^([^#]*)#?(.*)$")
  target, heading = vim.trim(target), vim.trim(heading)
  return { target = target, heading = heading ~= "" and heading or nil }
end

--- Links to other files (`![[image.png]]`, `[[doc.pdf]]`) are not note links.
local function is_note_target(target)
  local ext = target:match("%.([%w]+)$")
  return not ext or ext:lower() == "md"
end

--- Note link targets in `text` (string or list of lines), unique, in order. Links inside
--- code are ignored, as are same-note links (`[[#heading]]`) and links to non-markdown files.
function M.parse(text)
  local found, seen = {}, {}
  for _, line in ipairs(require("notes.markdown").prose(text)) do
    for inner in line:gmatch("%[%[(.-)%]%]") do
      local target = parse_inner(inner).target
      if target ~= "" and is_note_target(target) and not seen[target] then
        seen[target] = true
        found[#found + 1] = target
      end
    end
  end
  return found
end

--- The link under byte column `col` (0-based) of `line`, as `{ target, heading? }`, or nil.
function M.link_at(line, col)
  local init = 1
  while true do
    local s, e, inner = line:find("%[%[(.-)%]%]", init)
    if not s then
      return nil
    end
    if col + 1 >= s and col + 1 <= e then
      return parse_inner(inner)
    end
    init = e + 1
  end
end

--- Comparison key for a note path or link target: separators unified, `.md` dropped,
--- each segment slugified, so `[[Meeting Notes]]` matches `meeting-notes.md`.
local function key(path)
  local slugify = require("notes.note").slugify
  local segments = {}
  for segment in path:gsub("%.md$", ""):gmatch("[^/\\]+") do
    segments[#segments + 1] = slugify(segment)
  end
  return table.concat(segments, "/")
end

--- Build a resolver over `notes` (from note.list()). The returned function maps a link
--- target to the matching notes: an exact path match wins; otherwise any note whose path
--- ends with the target (`[[meeting]]` -> `work/meeting.md`). A leading `/` only allows
--- exact matches from the notes root.
function M.resolver(notes)
  local by_basename = {}
  for _, n in ipairs(notes) do
    local k = key(n.name)
    local base = k:match("[^/]+$") or k
    by_basename[base] = by_basename[base] or {}
    table.insert(by_basename[base], { key = k, note = n })
  end

  return function(target)
    local rooted = target:match("^[/\\]") ~= nil
    local k = key(target)
    local candidates = by_basename[k:match("[^/]+$") or k] or {}
    local exact, suffix = {}, {}
    for _, c in ipairs(candidates) do
      if c.key == k then
        exact[#exact + 1] = c.note
      elseif not rooted and vim.endswith(c.key, "/" .. k) then
        suffix[#suffix + 1] = c.note
      end
    end
    return #exact > 0 and exact or suffix
  end
end

--- Notes `target` resolves to.
function M.resolve(target)
  return M.resolver(require("notes.note").list())(target)
end

--- Move the cursor to the first heading whose text matches `heading` (case-insensitive).
local function jump_to_heading(heading)
  local wanted = vim.trim(heading):lower()
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local text = line:match("^#+%s+(.-)%s*#*%s*$")
    if text and text:lower() == wanted then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return true
    end
  end
  return false
end

local function open(path, heading)
  require("notes.note").open(path)
  if heading then
    jump_to_heading(heading)
  end
end

--- Follow the `[[link]]` under the cursor. Returns false when the cursor is not on a link
--- (so callers can fall back to the key's normal behaviour).
--- One match opens it; several open a picker; none offers to create the note.
function M.follow()
  local link = M.link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2])
  if not link then
    return false
  end
  if link.target == "" then
    if link.heading and not jump_to_heading(link.heading) then
      vim.notify("notes: no heading " .. link.heading, vim.log.levels.INFO)
    end
    return true
  end
  if not is_note_target(link.target) then
    vim.notify("notes: [[" .. link.target .. "]] is not a note link", vim.log.levels.INFO)
    return true
  end

  local matches = M.resolve(link.target)
  if #matches == 1 then
    open(matches[1].path, link.heading)
  elseif #matches > 1 then
    require("notes.pickers").pick(matches, { prompt = "[[" .. link.target .. "]]" }, function(item)
      open(item.path, link.heading)
    end)
  else
    local create = not config.options.links.confirm_create
      or vim.fn.confirm(("Create note %q?"):format(link.target), "&Yes\n&No", 1) == 1
    if create then
      require("notes.note").create(link.target)
    end
  end
  return true
end

--- Notes that link to `path`, as paths sorted alphabetically.
function M.backlinks(path)
  local notes = require("notes.note").list()
  local resolve = M.resolver(notes)
  local result = {}
  for from, entry in pairs(require("notes.index").refresh()) do
    if not fs.same(from, path) then
      for _, target in ipairs(entry.links) do
        local hit = vim.tbl_contains(resolve(target), function(n)
          return fs.same(n.path, path)
        end, { predicate = true })
        if hit then
          result[#result + 1] = from
          break
        end
      end
    end
  end
  table.sort(result)
  return result
end

--- Add the follow-link keymaps to `buf` if it is a note (markdown inside the notes dir).
function M.attach(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.b[buf].notes_links or name == "" or not fs.is_inside(name, config.dir()) then
    return
  end
  vim.b[buf].notes_links = true
  for _, lhs in ipairs(config.options.links.keys) do
    vim.keymap.set("n", lhs, function()
      if not M.follow() then
        -- Not on a link: do what the key normally does.
        vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
      end
    end, { buffer = buf, desc = "Notes: follow [[link]]" })
  end
end

return M
