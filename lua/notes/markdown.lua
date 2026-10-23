local M = {}

--- Opening code fence (``` or ~~~, 3+ chars) on `line`, as the fence string, or nil.
local function fence(line)
  return line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
end

--- The lines of `text` (string or list of lines) with code removed: lines inside fenced
--- code blocks (and the fences) become "", inline code spans become a space. Line
--- numbers are preserved.
function M.prose(text)
  local lines = type(text) == "table" and text or vim.split(text, "\r?\n")
  local result = {}
  local open_fence
  for i, line in ipairs(lines) do
    local f = fence(line)
    if open_fence then
      -- A fence closes with the same character, at least as long as the opener.
      if f and f:sub(1, 1) == open_fence:sub(1, 1) and #f >= #open_fence and line:match("^%s*[`~]+%s*$") then
        open_fence = nil
      end
      result[i] = ""
    elseif f then
      open_fence = f
      result[i] = ""
    else
      result[i] = line:gsub("(`+).-%1", " ")
    end
  end
  return result
end

return M
