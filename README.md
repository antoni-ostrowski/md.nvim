# md.nvim

`.md` buf → PNG → `vsplit`. No image display impl, kitty protocol etc up to end user (`snacks.image`, `image.nvim`, ...).

## Renderers

- `mdimg` (default when found): GitHub-style HTML → headless Chrome screenshot. Pretty: tables, highlight.js code, Mermaid.
- `md2png` (fallback): zero-dep Go binary, basic styling. Auto-downloaded.

```sh
bun add -g mdimg
# first render downloads Chrome (~150MB) via puppeteer, one time
```

Force one:

```lua
require("md").setup({ renderer = "mdimg" })   -- or "md2png", "auto"
```

`md2png`-only manual install / update:

```
:MdInstallBin
```

## Install

`vim.pack`:

```lua
vim.pack.add({ { src = "https://github.com/YOU/md.nvim" } })
require("md").setup({
  -- renderer = "auto", -- "mdimg" | "md2png"
  -- mdimg_cmd = "mdimg",
  -- css = "github",      -- light template (see mdimg template/css/)
  -- css_dark = "githubDark",
  -- width = 800,
  -- margin = 48,         -- md2png only
  -- pt = 16,             -- md2png only
  -- theme = "light",     -- or "dark"
  -- extra_args = {},
  -- output_dir = vim.fn.stdpath("cache") .. "/md-nvim",
  -- pages = { auto = true, height = 1200 }, -- tall png → sliced pages, scroll with j/k
  -- open_cmd = "vsplit",
})
```

## Use

Edit `.md`, then:

```
:MdRenderImage
:MdRenderImage dark
:MdRenderImage light
```

Lua:

```lua
require("md").render()
require("md").render({ theme = "dark", width = 1000 })
```

Output: `<cache>/md-nvim/<bufname>-<time>.png`, opened via `vsplit`. Delete old files manually.

## Scrolling (tall docs)

`snacks.image` image buffers always fit whole PNG to window (`buf.lua` `auto_resize` + `util.fit`) — buffer has ~1 line, so `j/k C-d` can't scroll pixels.

Our fix: if PNG taller than `pages.height`, slice via `magick -crop` into `*-p0.png, *-p1.png…` and open a `*-pages.md` with stacked `![](...)` refs. `snacks` renders each inline → normal vim motions scroll.

Req for paging: `magick` in `PATH`. Short docs → single PNG as before. Disable with `setup({ pages = { auto = false } })`.
