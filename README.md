# md.nvim

`.md` buf → PNG via `md2png` → `vsplit`. No image display impl, kitty protocol etc up to end user (`snacks.image`, `image.nvim`, ...).

## Req

None. Bundled `md2png v0.5.17` auto-downloads on first `:MdRenderImage` to `stdpath("data")/md-nvim/bin/`.

Manual install / update:

```
:MdInstallBin
```

Override if you want system bin:

```lua
require("md").setup({ cmd = "md2png" })

## Install

lazy.nvim:

```lua
{
  "you/md.nvim",
  ft = "markdown",
  config = function()
    require("md").setup({
      -- cmd = "md2png",
      -- width = 1024,
      -- margin = 48,
      -- pt = 16,
      -- theme = "light", -- or "dark"
      -- extra_args = {}, -- e.g. { "-footnote-links=false" }
      -- output_dir = vim.fn.stdpath("cache") .. "/md-nvim",
      -- pages = { auto = true, height = 1200 }, -- tall png → sliced pages, scroll with j/k
  -- open_cmd = "vsplit",
    })
  end,
}
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
require("md").render({ theme = "dark", width = 1400 })
```

Output: `<cache>/md-nvim/<bufname>-<time>.png`, opened via `vsplit`. Delete old files manually.

## Scrolling (tall docs)

`snacks.image` image buffers always fit whole PNG to window (`buf.lua` `auto_resize` + `util.fit`) — buffer has ~1 line, so `j/k C-d` can't scroll pixels.

Our fix: if PNG taller than `pages.height`, slice via `magick -crop` into `*-p0.png, *-p1.png…` and open a `*-pages.md` with stacked `![](...)` refs. `snacks` renders each inline → normal vim motions scroll.

Req for paging: `magick` in `PATH` (you have it). Short docs → single PNG as before. Disable with `setup({ pages = { auto = false } })`.
