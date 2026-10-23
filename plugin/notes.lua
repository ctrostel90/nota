if vim.g.loaded_notes then
  return
end
vim.g.loaded_notes = true

if vim.fn.has("nvim-0.11") ~= 1 then
  vim.notify("notes: requires Neovim 0.11+", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("NotesNew", function(cmd)
  require("notes").new(cmd.args ~= "" and cmd.args or nil)
end, {
  nargs = "?",
  desc = "Create a new note (folder/name; prompts when omitted)",
  complete = function(arglead)
    return require("notes.note").complete(arglead)
  end,
})

vim.api.nvim_create_user_command("NotesNewFrom", function(cmd)
  local template, name = cmd.args:match("^(%S+)%s*(.*)$")
  require("notes").new_from(template, name ~= "" and name or nil)
end, {
  nargs = "*",
  desc = "Create a new note from a template ({template} [folder/name]; picks when omitted)",
  complete = function(arglead, cmdline)
    return require("notes.note").complete_from(arglead, cmdline)
  end,
})

vim.api.nvim_create_user_command("NotesToday", function()
  require("notes").today()
end, { desc = "Open or create today's daily note" })

vim.api.nvim_create_user_command("NotesFind", function()
  require("notes").find()
end, { desc = "Find a note by name" })

vim.api.nvim_create_user_command("NotesGrep", function()
  require("notes").grep()
end, { desc = "Search the contents of all notes" })
