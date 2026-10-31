local M = {}

---@class md.PagesConfig
---@field auto boolean slice tall png into pages for vim-motion scroll, default true
---@field height integer page height in px, default 1200
---@field overlap integer reserved, unused for now

---@class md.Config
---@field renderer "auto"|"mdimg"|"md2png" which backend; auto = mdimg if found else md2png
---@field mdimg_cmd string mdimg binary, default "mdimg" (bun add -g mdimg)
---@field css string mdimg css template for light theme
---@field css_dark string mdimg css template for dark theme
---@field cmd? string md2png binary override; nil = bundled bin in stdpath(data)
---@field version? string pinned md2png release, default in md/bin.lua
---@field width integer image width px
---@field margin integer margin px (md2png only)
---@field pt integer base font size pt (md2png only)
---@field theme string "light"|"dark"
---@field extra_args string[] extra CLI args passed to the renderer
---@field output_dir string dir for tmp md/png
---@field open_cmd string how to open png, default "vsplit"
---@field pages md.PagesConfig
M.config = {
  renderer = "auto",
  mdimg_cmd = "mdimg",
  css = "github",
  css_dark = "githubDark",
  cmd = nil,
  version = nil,
  width = 800,
  margin = 48,
  pt = 16,
  theme = "light",
  extra_args = {},
  output_dir = vim.fn.stdpath("cache") .. "/md-nvim",
  open_cmd = "vsplit",
  pages = { auto = true, height = 1200, overlap = 0 },
}

---@param opts md.Config?
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M.config.version then
    require("md.bin").version = M.config.version
  end
  vim.fn.mkdir(M.config.output_dir, "p")
end

local function notify(msg, level)
  vim.notify("[md.nvim] " .. msg, level or vim.log.levels.INFO)
end

---@param path string png file
---@return integer? w, integer? h (reads IHDR, no deps)
local function png_size(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil, nil
  end
  local header = fd:read(24)
  fd:close()
  if not header or #header < 24 then
    return nil, nil
  end
  if header:sub(1, 8) ~= "\137PNG\r\n\26\n" then
    return nil, nil
  end
  local w = header:byte(17) * 16777216 + header:byte(18) * 65536 + header:byte(19) * 256 + header:byte(20)
  local h = header:byte(21) * 16777216 + header:byte(22) * 65536 + header:byte(23) * 256 + header:byte(24)
  return w, h
end

local function magick_bin()
  if vim.fn.executable("magick") == 1 then
    return "magick"
  end
  if vim.fn.executable("convert") == 1 then
    return "convert" -- IMv6
  end
  return nil
end

local function open_single(cfg, png)
  vim.cmd(cfg.open_cmd .. " " .. vim.fn.fnameescape(png))
end

-- Stacked pages in a markdown buffer → snacks doc.inline renders each,
-- normal j/k C-d C-u scroll works (single image buf can't scroll, it fits).
local function open_pages(cfg, pages, title)
  local lines = { "# " .. title .. " (" .. #pages .. " pages, j/k to scroll)", "" }
  for _, p in ipairs(pages) do
    lines[#lines + 1] = "![](" .. p .. ")"
    lines[#lines + 1] = ""
  end
  local md = pages[1]:gsub("-p%d+%.png$", "-pages.md")
  if vim.fn.writefile(lines, md) ~= 0 then
    notify("writefile failed: " .. md .. ", opening first page", vim.log.levels.WARN)
    open_single(cfg, pages[1])
    return
  end
  vim.cmd(cfg.open_cmd .. " " .. vim.fn.fnameescape(md))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function maybe_paginate(cfg, png, base)
  if not (cfg.pages and cfg.pages.auto) then
    open_single(cfg, png)
    return
  end
  local w, h = png_size(png)
  if not h or h <= cfg.pages.height then
    open_single(cfg, png)
    return
  end
  local mag = magick_bin()
  if not mag then
    notify("tall image (" .. h .. "px) but no magick → single view (no scroll)", vim.log.levels.WARN)
    open_single(cfg, png)
    return
  end
  local prefix = png:gsub("%.png$", "-p")
  local pattern = string.format("%dx%d", w or cfg.width, cfg.pages.height)
  notify(string.format("slicing %dpx → %dpx pages…", h, cfg.pages.height))
  vim.system({ mag, png, "-crop", pattern, "+repage", "+adjoin", prefix .. "%d.png" }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        notify("slice failed, opening single: " .. (res.stderr or ""), vim.log.levels.WARN)
        open_single(cfg, png)
        return
      end
      local pages = {}
      for i = 0, 64 do
        local p = string.format("%s%d.png", prefix, i)
        if vim.fn.filereadable(p) == 1 then
          pages[#pages + 1] = p
        else
          break
        end
      end
      if #pages <= 1 then
        open_single(cfg, png)
        return
      end
      open_pages(cfg, pages, base)
    end)
  end)
end

---@param opts md.Config? per-call override
function M.render(opts)
  local cfg = vim.tbl_deep_extend("force", M.config, opts or {})
  if cfg.version then
    require("md.bin").version = cfg.version
  end

  local function resolve_bin()
    if cfg.cmd and cfg.cmd ~= "" then
      return cfg.cmd
    end
    return require("md.bin").bin_path()
  end

  local function resolve_renderer()
    if cfg.renderer == "mdimg" or (cfg.renderer == "auto" and vim.fn.executable(cfg.mdimg_cmd) == 1) then
      return "mdimg"
    end
    return "md2png"
  end

  local function build_cmd(renderer, bin, tmp_md, tmp_png)
    if renderer == "mdimg" then
      local css = cfg.theme == "dark" and cfg.css_dark or cfg.css
      local cmd = { bin, "-i", tmp_md, "-o", tmp_png, "-w", tostring(cfg.width), "--css", css }
      for _, a in ipairs(cfg.extra_args) do
        table.insert(cmd, a)
      end
      return cmd
    end
    local cmd = {
      bin,
      "-in",
      tmp_md,
      "-out",
      tmp_png,
      "-width",
      tostring(cfg.width),
      "-margin",
      tostring(cfg.margin),
      "-pt",
      tostring(cfg.pt),
      "-theme",
      cfg.theme,
    }
    for _, a in ipairs(cfg.extra_args) do
      table.insert(cmd, a)
    end
    return cmd
  end

  local function do_render(bin, renderer)
    local src_buf = vim.api.nvim_get_current_buf()
    local src_name = vim.api.nvim_buf_get_name(src_buf)
    local base = vim.fn.fnamemodify(src_name, ":t:r")
    if base == "" then
      base = "untitled"
    end
    -- sanitize for tmp filename
    base = base:gsub("[^%w%-_%.]+", "_")

    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      notify("buffer empty, nothing to render", vim.log.levels.WARN)
      return
    end

    vim.fn.mkdir(cfg.output_dir, "p")
    local stamp = os.time()
    local tmp_md = string.format("%s/%s-%d.md", cfg.output_dir, base, stamp)
    local tmp_png = string.format("%s/%s-%d.png", cfg.output_dir, base, stamp)

    if vim.fn.writefile(lines, tmp_md) ~= 0 then
      notify("writefile failed: " .. tmp_md, vim.log.levels.ERROR)
      return
    end

    local cmd = build_cmd(renderer, bin, tmp_md, tmp_png)

    notify(renderer .. " rendering → " .. tmp_png)

    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          local err = (res.stderr or "") .. (res.stdout or "")
          notify(renderer .. " failed (" .. res.code .. "): " .. err, vim.log.levels.ERROR)
          return
        end
        if vim.fn.filereadable(tmp_png) == 0 then
          notify(renderer .. " exit 0 but no png: " .. tmp_png, vim.log.levels.ERROR)
          return
        end
        maybe_paginate(cfg, tmp_png, base)
      end)
    end)
  end

  local renderer = resolve_renderer()
  if renderer == "mdimg" then
    if vim.fn.executable(cfg.mdimg_cmd) == 0 then
      notify("mdimg not found → bun add -g mdimg", vim.log.levels.ERROR)
      return
    end
    do_render(cfg.mdimg_cmd, renderer)
    return
  end
  local bin = resolve_bin()
  if vim.fn.executable(bin) == 1 then
    do_render(bin, renderer)
    return
  end
  -- custom cmd missing → hard error, no auto-download
  if cfg.cmd and cfg.cmd ~= "" then
    notify("binary not found: " .. bin .. " → :MdInstallBin or fix cmd path", vim.log.levels.ERROR)
    return
  end
  -- bundled bin missing → fetch release asset then render
  require("md.bin").ensure(function(path, err)
    if not path then
      notify("install failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      return
    end
    do_render(path, "md2png")
  end)
end

return M
