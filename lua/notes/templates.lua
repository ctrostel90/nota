local config = require("notes.config")
local fs = require("notes.fs")

local M = {}

--- A config entry is either a spec table or bare content (string, function, list of lines).
local function as_spec(entry)
  if entry == nil then
    return nil
  end
  if type(entry) == "table" and not vim.islist(entry) then
    return entry
  end
  return { template = entry }
end

local function template_file(name)
  local dir = config.options.template_dir
  if not dir then
    return nil
  end
  local path = fs.join(fs.normalize(dir), name .. ".md")
  if vim.fn.filereadable(path) == 1 then
    return path
  end
end

--- Fields may be given as `"customer"` or `{ name = "customer", prompt = "Customer: " }`.
local function normalize_fields(fields)
  return vim.tbl_map(function(field)
    if type(field) == "string" then
      field = { name = field }
    end
    return { name = field.name, prompt = field.prompt or (field.name:gsub("^%l", string.upper) .. ": ") }
  end, fields or {})
end

function M.validate(name, entry)
  local prefix = "templates." .. name
  vim.validate(prefix, entry, { "string", "function", "table" })
  local spec = as_spec(entry)
  vim.validate(prefix .. ".template", spec.template, { "string", "function", "table" }, true)
  vim.validate(prefix .. ".dir", spec.dir, "string", true)
  vim.validate(prefix .. ".name", spec.name, "string", true)
  vim.validate(prefix .. ".fields", spec.fields, "table", true)
  for i, field in ipairs(spec.fields or {}) do
    local key = type(field) == "table" and field.name or field
    vim.validate(("%s.fields[%d]"):format(prefix, i), key, function(k)
      return type(k) == "string" and k:match("^[%w_]+$") ~= nil
    end, "a field name of letters, digits or _")
  end
end

--- Names of all templates: built-ins, config entries, and files in `template_dir`.
function M.names()
  local seen, names = {}, {}
  local function add(name)
    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for name in pairs(config.defaults.templates) do
    add(name)
  end
  for name in pairs(config.options.templates) do
    add(name)
  end
  local dir = config.options.template_dir
  if dir then
    for _, rel in ipairs(fs.list_files(fs.normalize(dir), ".md", 1)) do
      add(rel:sub(1, -4))
    end
  end
  table.sort(names)
  return names
end

--- Resolve a template by name. Content comes from the config entry's `template`, then
--- `template_dir/<name>.md`, then the built-in, then the `default` template's content.
--- Returns the spec, or `nil, err` for unknown names.
function M.get(name)
  local user = as_spec(config.options.templates[name])
  local builtin = as_spec(config.defaults.templates[name])
  local file = template_file(name)
  if not (user or builtin or file) then
    return nil, ("unknown template %q"):format(name)
  end
  user, builtin = user or {}, builtin or {}

  local content = user.template or file or builtin.template
  if content == nil then
    content = M.get("default").template
  end
  return {
    name = name,
    template = content,
    path = file,
    dir = user.dir or builtin.dir or "",
    pattern = user.name or builtin.name or "{{slug}}",
    fields = normalize_fields(user.fields or builtin.fields),
  }
end

return M
