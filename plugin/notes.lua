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
