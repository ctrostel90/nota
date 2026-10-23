# nvim-note-taker — plan

Neovim 0.11+, pure Lua, Windows + Linux. Only external dependency: ripgrep (for full-text grep).

## Decisions

- **Picker**: adapter layer; auto-detect telescope → fzf-lua → snacks → `vim.ui.select`.
- **Files**: subfolders allowed (`work/meeting-notes` creates `work/`). Empty name → timestamp (`20261023-143012.md`).
- **Tags**: inline `#tags` anywhere, pattern `#[%w_/-]+` (nested `#work/plc` ok). Ignored: headings, fenced/inline code, mid-word/URL `#`.
- **Links**: `[[name]]` resolves by filename anywhere in the tree; `[[work/name]]` disambiguates. Multiple matches → picker; none → offer to create.
- **Completion**: shared core feeding blink.cmp, nvim-cmp, and omnifunc. `#` → tags, `[[` → note names.
- **Index**: built lazily via `vim.fs.dir`, updated per-file on `BufWritePost`.
- **New notes**: opened as unsaved buffers; nothing is written (and no folder created) until the user saves.
- **Named templates**: see below. Chosen via `:NotesNewFrom`; custom keymaps via the Lua API.

## Named templates (milestone 3)

Templates beyond `default`, e.g. internal vs. customer meetings, each with its own content,
folder, filename pattern, and extra prompted fields.

```lua
require("notes").setup({
  template_dir = "~/notes/.templates",   -- optional: every *.md here is a template named after the file
  templates = {
    default = "# {{title}}\n\n{{cursor}}",
    daily = { template = "# {{date}}\n\n{{cursor}}", dir = "daily", name = "{{date:%Y-%m-%d}}" },
    internal = {
      template = "~/notes/.templates/internal.md",
      dir = "meetings/internal",
      name = "{{date:%Y-%m-%d}}-{{slug}}",
    },
    customer = {
      -- no `template` key: content comes from template_dir/customer.md
      dir = "meetings/customers",
      name = "{{date:%Y-%m-%d}}-{{customer}}-{{slug}}",
      fields = { { name = "customer", prompt = "Customer: " } },
    },
  },
})

-- user-defined keymaps
vim.keymap.set("n", "<leader>ntc", function() require("notes").new({ template = "customer" }) end)
```

### Commands and API

- `:NotesNew [name]`: unchanged; uses `default`.
- `:NotesNewFrom {template} [name]`: first arg tab-completes template names. With no args, pick a
  template with the picker, then prompt for the name.
- `:NotesToday`: shorthand for the `daily` template with an empty name, no prompt.
- `require("notes").new(opts)`: `opts` is a name string (as today) or
  `{ template?, name?, fields? }`. Missing `name` prompts for it; missing `fields` values prompt for them.

### Template spec

A template is a string, a file path, a function(ctx), or a table:

| key        | meaning                                                                 | default          |
|------------|-------------------------------------------------------------------------|------------------|
| `template` | content: string / file path / function(ctx)                             | `template_dir/<name>.md` |
| `dir`      | folder relative to the notes root                                       | root             |
| `name`     | filename pattern (without `.md`)                                        | `{{slug}}`       |
| `fields`   | ordered `{ name, prompt }` list, prompted after the note name           | none             |

### Placeholders

- Content and filename: `{{title}}`, `{{slug}}`, `{{date}}`, `{{time}}`, `{{date:<strftime>}}`,
  and each field (`{{customer}}`). `{{cursor}}` is content-only.
- Values are inserted as typed into content and slugified in filenames.
- In filenames, empty values are dropped along with the separators around them, so
  `{{date}}-{{slug}}` with an empty name gives `2026-10-23`. If the whole name comes out empty,
  the timestamp is used.

### Resolution rules

- Template names come from `template_dir` files plus `templates` config entries. A config entry
  with the same name adds or overrides `dir`, `name`, `fields` and `template`.
- A folder typed in the name (`other/x`) replaces the template's `dir`. It's relative to the notes root.
- If the generated filename already exists, that note is opened. This is how `daily` reuses
  today's note.
- An unknown template name is an error notification and nothing is created.
- `daily_dir` / `daily_format` (milestone 2) are replaced by the `daily` template's `dir` / `name`.

## Layout

```
plugin/notes.lua            -- :Notes* commands, lazy-requires the rest
lua/notes/
  init.lua                  -- setup(), public API
  config.lua                -- defaults, merge, validation
  fs.lua                    -- path normalize/join, mkdir -p, dir walk, "inside notes dir"
  note.lua                  -- new note, daily note, filename/slug/timestamp, templates
  index.lua                 -- name→paths, tags→paths, links/backlinks
  tags.lua                  -- #tag parser
  links.lua                 -- [[link]] parse/resolve/follow/backlinks
  completion/{core,blink,cmp,omni}.lua
  pickers/{init,telescope,fzf_lua,snacks,select}.lua
doc/notes.txt
tests/
```

## Windows gotchas

- Case-insensitive, separator-normalized path comparison for "is this buffer a note".
- No autocmd file patterns for the notes dir; check paths in Lua callbacks.
- Slugify away `: * ? " < > |` and reserved names (`CON`, `NUL`, ...).
- Notes written with LF line endings.

## Milestones

1. [x] `fs`, `config`, `NotesNew` (subfolders, auto timestamp, templates)
2. [x] Picker adapter + `vim.ui.select` backend, `NotesFind`, `NotesToday`
3. [x] Named templates: template specs (`dir`, `name` pattern, `fields`), `template_dir`,
       `{{date:fmt}}`, `:NotesNewFrom`, `new({ template = ... })`, `daily` folded into templates
4. [ ] Telescope / fzf-lua / snacks backends, `NotesGrep`
5. [ ] Tag parser + index, `NotesTags`
6. [ ] Wiki links: follow, create-on-missing, backlinks
7. [ ] Completion: core → omnifunc → blink → cmp
8. [ ] Docs, tests, CI matrix (ubuntu + windows)
