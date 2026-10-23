# nvim-note-taker

Markdown notes for Neovim: quick capture, templates, `#tags`, `[[wiki links]]`, and fuzzy
finding through the picker you already use. Works the same on Windows and Linux.

- **New notes** in a folder you choose, with subfolders (`work/meeting-notes`), timestamp
  names when you skip the name, and templates. New notes open as unsaved buffers; nothing is
  written until you save.
- **Named templates** (e.g. internal vs. customer meetings) with their own folder, filename
  pattern and prompted fields.
- **Find** notes by name and tags, **grep** their contents, filter **by one or more tags**.
- **Wiki links**: follow `[[links]]` with `<CR>`/`gf`, create missing notes, list backlinks.
- **Completion** of `#tags` and `[[links]]` for blink.cmp, nvim-cmp, or the built-in omnifunc.
- **Pickers**: telescope, fzf-lua or snacks (auto-detected), falling back to `vim.ui.select`.

## Requirements

- Neovim 0.11+
- [ripgrep](https://github.com/BurntSushi/ripgrep) for `:NotesGrep` (everything else is pure Lua)
- Optional: telescope.nvim, fzf-lua or snacks.nvim; blink.cmp or nvim-cmp

## Install

lazy.nvim:

```lua
{
  "<owner>/nvim-note-taker",          -- or: dir = "C:/Tools/nvim-note-taker" for a local checkout
  opts = {
    dir = "~/notes",
  },
}
```

Or call `require("notes").setup({ ... })` yourself. Commands work without `setup()`, using
the defaults; keymaps and link/completion integration need it.

## Commands and keymaps

| Command                        | Key           | Does |
|--------------------------------|---------------|------|
| `:NotesNew [folder/name]`      | `<leader>nn`  | New note from the `default` template (prompts when no name; empty = timestamp) |
| `:NotesNewFrom {tpl} [name]`   |               | New note from a named template (no args: pick a template) |
| `:NotesToday`                  | `<leader>nd`  | Open or create today's note (`daily` template) |
| `:NotesFind`                   | `<leader>nf`  | Fuzzy find notes by name and tags, newest first |
| `:NotesGrep`                   | `<leader>ng`  | Search note contents (ripgrep) |
| `:NotesTags [tag ... -tag]`    | `<leader>n#`  | Pick a tag then a note, or list notes with all given tags and none of the `-` ones |
| `:NotesBacklinks`              | `<leader>nb`  | Notes that link to the current one |

In notes, `<CR>` and `gf` follow the `[[link]]` under the cursor (and behave normally
elsewhere). Set any key to `false` in `keymaps` (or `links.keys = {}`) to disable it.

## Configuration

Defaults:

```lua
require("notes").setup({
  dir = "~/notes",
  templates = {
    default = "# {{title}}\n\n{{cursor}}",
    daily = { template = "# {{date}}\n\n{{cursor}}", dir = "daily", name = "{{date:%Y-%m-%d}}" },
  },
  template_dir = nil,              -- folder of <name>.md template files
  date_format = "%Y-%m-%d",
  time_format = "%H:%M",
  timestamp_format = "%Y%m%d-%H%M%S",
  picker = "auto",                 -- "telescope" | "fzf-lua" | "snacks" | "select"
  find_tags = true,                -- show tags in note lists so fuzzy search matches them
  links = {
    keys = { "<CR>", "gf" },
    confirm_create = true,         -- ask before creating the target of a dangling [[link]]
  },
  completion = { omnifunc = true },
  start_insert = true,             -- insert mode at {{cursor}} in new notes
  keymaps = {
    new = "<leader>nn",
    today = "<leader>nd",
    find = "<leader>nf",
    grep = "<leader>ng",
    tags = "<leader>n#",
    backlinks = "<leader>nb",
  },
})
```

### Templates

A template is a string, a path to a file, a `function(ctx)` returning a string or lines, or a
table:

```lua
templates = {
  internal = {
    template = "# {{title}}\nDate: {{date}}\n\n#meeting #internal\n\n## Notes\n{{cursor}}",
    dir = "meetings/internal",
    name = "{{date:%Y-%m-%d}}-{{slug}}",
  },
  customer = {
    -- no `template`: content comes from template_dir/customer.md (or the default template)
    dir = "meetings/customers",
    name = "{{date:%Y-%m-%d}}-{{customer}}-{{slug}}",
    fields = { { name = "customer", prompt = "Customer: " } },  -- or just { "customer" }
  },
}
```

| Placeholder          | Value |
|----------------------|-------|
| `{{title}}`          | The name as typed (`Meeting Notes`); date and time when empty |
| `{{slug}}`           | Filename-safe name (`meeting-notes`) |
| `{{date}}`, `{{time}}` | Using `date_format` / `time_format` |
| `{{date:%Y}}`        | Any `strftime` format |
| `{{<field>}}`        | A prompted field |
| `{{cursor}}`         | Cursor position (content only) |

In filenames, values are slugified and separators left by empty values are dropped
(`{{date}}-{{slug}}` with no name gives `2026-10-23`). A folder typed in the name
(`other/x`) replaces the template's `dir`; `/x` means the notes root. If the resulting note
exists it is opened instead.

Your entries are merged with the built-ins per template, so `daily = "# Day {{date}}"`
changes the content but keeps the `daily/` folder and date filename.

Bind your own keys to templates:

```lua
vim.keymap.set("n", "<leader>ntc", function() require("notes").new({ template = "customer" }) end)
vim.keymap.set("n", "<leader>nti", function() require("notes").new({ template = "internal" }) end)
```

### Tags

`#tag` at the start of a line or after whitespace: letters (including non-ASCII), digits,
`_`, `-`, `/`. Tags are case-insensitive and nested tags count for their parents (`#work/plc`
is also `#work`). Headings, `C#`, `page#anchor`, `(#section)`, numbers like `#123`, and code
are ignored.

- Fuzzy: `:NotesFind` and type `#meeting #plc` (any order).
- Exact: `:NotesTags meeting plc -draft`.

### Links

`[[name]]`, `[[folder/name]]`, `[[name|alias]]`, `[[name#Heading]]`, `[[#Heading]]`.
Names match case- and space-insensitively (`[[Meeting Notes]]` finds `meeting-notes.md`)
anywhere in the notes tree; an exact path wins, `[[/name]]` only matches at the root.
Several matches open a picker; none offers to create the note.

### Completion

Typing `#` suggests tags and `[[` suggests notes (by path or title, with a preview), only
in notes.

- **blink.cmp**:
  ```lua
  sources = {
    default = { "lsp", "path", "snippets", "notes" },
    providers = { notes = { name = "Notes", module = "notes.completion.blink" } },
  },
  ```
- **nvim-cmp**: `setup()` registers the source; add `{ name = "notes" }` to your sources.
- **omnifunc**: `<C-x><C-o>` in notes (`completion.omnifunc = true`).

## Lua API

```lua
local notes = require("notes")
notes.new()                                   -- prompt for a name
notes.new("work/Sprint review")
notes.new({ template = "customer", name = "Kickoff", fields = { customer = "Acme" } })
notes.new_from()                              -- pick a template
notes.today()
notes.find()
notes.grep()
notes.tags()                                  -- or notes.tags("meeting -draft")
notes.backlinks()
notes.follow_link()                           -- returns false when not on a link
```

## Development

```sh
nvim -l tests/all.lua            # all suites; fetches pinned test plugins into .tests/
nvim -l tests/all.lua pickers    # only matching suites
```

Suites: unit tests, picker backends (telescope, fzf-lua, snacks), and completion engines
(blink.cmp, nvim-cmp, omnifunc) driven with real keystrokes in a child Neovim. CI runs them
on Ubuntu and Windows against Neovim 0.11.5 and stable.
