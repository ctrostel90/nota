local M = {}

-- Tag characters: ASCII letters/digits, `_`, `-`, `/`, and any non-ASCII byte (UTF-8 letters).
local TAG = "#([%w_/%-\128-\255]+)"

--- Opening code fence (``` or ~~~, 3+ chars) on `line`, as the fence string, or nil.
local function fence(line)
  return line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
end

local function normalize(tag)
  tag = tag:gsub("[/%-]+$", ""):lower()
  -- At least one non-digit, so `#123` (issue numbers) is not a tag.
  if tag == "" or not tag:find("[^%d/%-_]") then
    return nil
  end
  return tag
end

--- Tags in `text` (string or list of lines), lowercased, unique, in order of appearance.
--- A tag is `#` at line start or after whitespace; headings (`# x`), mid-word `#`
--- (`C#`, `page#anchor`), fenced code blocks and inline code are ignored.
function M.parse(text)
  local lines = type(text) == "table" and text or vim.split(text, "\r?\n")
  local found, seen = {}, {}
  local open_fence

  for _, line in ipairs(lines) do
    local f = fence(line)
    if open_fence then
      -- A fence closes with the same character, at least as long as the opener.
      if f and f:sub(1, 1) == open_fence:sub(1, 1) and #f >= #open_fence and line:match("^%s*[`~]+%s*$") then
        open_fence = nil
      end
    elseif f then
      open_fence = f
    else
      line = line:gsub("(`+).-%1", " ")
      -- Leading space so a tag at line start matches the "after whitespace" rule.
      for raw in (" " .. line):gmatch("%s" .. TAG) do
        local tag = normalize(raw)
        if tag and not seen[tag] then
          seen[tag] = true
          found[#found + 1] = tag
        end
      end
    end
  end
  return found
end

--- `work/plc/io` -> { "work", "work/plc", "work/plc/io" }
function M.with_parents(tag)
  local result, prefix = {}, nil
  for part in tag:gmatch("[^/]+") do
    prefix = prefix and (prefix .. "/" .. part) or part
    result[#result + 1] = prefix
  end
  return result
end

return M
