if vim.g.loaded_md_nvim then
  return
end
vim.g.loaded_md_nvim = true

vim.api.nvim_create_user_command("MdInstallBin", function()
  require("md.bin").ensure(function(path, err)
    if not path then
      vim.notify("[md.nvim] install failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end)
end, {
  desc = "Download bundled md2png binary for this OS/arch",
})

vim.api.nvim_create_user_command("MdRenderImage", function(cmd_opts)
  local opts = {}
  -- :MdRenderImage dark → theme override
  if cmd_opts.args == "dark" or cmd_opts.args == "light" then
    opts.theme = cmd_opts.args
  end
  require("md").render(opts)
end, {
  nargs = "?",
  complete = function()
    return { "light", "dark" }
  end,
  desc = "Render current markdown buffer to PNG (md2png) and open in split",
})
