# nvim-note-taker — plan

Neovim 0.11+, pure Lua, Windows + Linux. Only external dependency: ripgrep (for full-text grep).

## Decisions

- **Picker**: adapter layer; auto-detect telescope → fzf-lua → snacks → `vim.ui.select`.
- **Files**: subfolders allowed (`work/meeting-notes` creates `work/`). Empty name → timestamp (`20261023-143012.md`).
- **Tags**: inline `#tags` anywhere, pattern `#[%w_/-]+` (nested `#work/plc` ok). Ignored: headings, fenced/inline code, mid-word/URL `#`.
- **Links**: `[[name]]` resolves by filename anywhere in the tree; `[[work/name]]` disambiguates. Multiple matches → picker; none → offer to create.
- **Completion**: shared core feeding blink.cmp, nvim-cmp, and omnifunc. `#` → tags, `[[` → note names.
- **Index**: built lazily via `vim.fs.dir`, updated per-file on `BufWritePost`.

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
3. [ ] Telescope / fzf-lua / snacks backends, `NotesGrep`
4. [ ] Tag parser + index, `NotesTags`
5. [ ] Wiki links: follow, create-on-missing, backlinks
6. [ ] Completion: core → omnifunc → blink → cmp
7. [ ] Docs, tests, CI matrix (ubuntu + windows)
