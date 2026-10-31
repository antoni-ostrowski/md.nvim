local M = {}

M.version = "v0.5.17"

local function data_dir()
  return vim.fn.stdpath("data") .. "/md-nvim/bin"
end

function M.bin_path()
  local dir = data_dir()
  if vim.fn.has("win32") == 1 then
    return dir .. "/md2png.exe"
  end
  return dir .. "/md2png"
end

local function asset_name()
  local sys = vim.uv.os_uname().sysname:lower() -- darwin, linux, windows / freebsd
  local mach = vim.uv.os_uname().machine:lower() -- arm64, aarch64, x86_64 ...
  local ver = M.version:gsub("^v", "")

  local arch = nil
  if mach == "arm64" or mach == "aarch64" then
    arch = "arm64"
  elseif mach == "x86_64" or mach == "amd64" then
    arch = "x86_64"
  elseif mach == "i386" or mach == "i686" then
    arch = "i386"
  end
  if arch == nil then
    return nil, "unsupported arch: " .. mach
  end

  if sys == "darwin" or sys:find("mac") then
    if arch == "arm64" then
      return string.format("md2png_%s_macOS_arm64.tar.gz", ver)
    else
      return string.format("md2png_%s_macOS_x86_64.tar.gz", ver)
    end
  elseif sys == "linux" then
    if arch == "arm64" then
      return string.format("md2png_%s_Linux_arm64.tar.gz", ver)
    elseif arch == "x86_64" then
      return string.format("md2png_%s_Linux_x86_64.tar.gz", ver)
    else
      return string.format("md2png_%s_Linux_i386.tar.gz", ver)
    end
  elseif sys:find("windows") or vim.fn.has("win32") == 1 then
    if arch == "arm64" then
      return string.format("md2png_%s_Windows_arm64.zip", ver)
    elseif arch == "x86_64" then
      return string.format("md2png_%s_Windows_x86_64.zip", ver)
    else
      return string.format("md2png_%s_Windows_i386.zip", ver)
    end
  end
  return nil, "unsupported os: " .. sys
end

function M.download_url()
  local asset, err = asset_name()
  if not asset then
    return nil, err
  end
  return string.format("https://github.com/arran4/md2png/releases/download/%s/%s", M.version, asset), asset
end

---@param cb fun(path?: string, err?: string)
function M.ensure(cb)
  cb = cb or function() end
  local bin = M.bin_path()
  if vim.fn.executable(bin) == 1 then
    cb(bin)
    return
  end
  local url, asset = M.download_url()
  if not url then
    cb(nil, asset)
    return
  end
  local dir = data_dir()
  vim.fn.mkdir(dir, "p")
  local tmp = dir .. "/" .. asset

  vim.notify("[md.nvim] downloading md2png " .. M.version .. " → " .. tmp)

  local curl = { "curl", "-fL", "-o", tmp, url }
  vim.system(curl, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(nil, "curl failed (" .. res.code .. "): " .. (res.stderr or ""))
        return
      end
      local extract
      if asset:match("%.zip$") then
        extract = { "unzip", "-o", tmp, "-d", dir }
      else
        extract = { "tar", "-xzf", tmp, "-C", dir }
      end
      vim.system(extract, { text = true }, function(res2)
        vim.schedule(function()
          pcall(vim.fn.delete, tmp)
          if res2.code ~= 0 then
            cb(nil, "extract failed: " .. (res2.stderr or ""))
            return
          end
          -- tarballs contain bare `md2png`, zips contain `md2png.exe`
          if vim.fn.has("win32") == 0 and vim.fn.filereadable(bin) == 1 then
            vim.fn.system({ "chmod", "+x", bin })
          end
          -- macOS gatekeeper: strip quarantine if present
          if vim.fn.has("mac") == 1 then
            pcall(vim.system, { "xattr", "-d", "com.apple.quarantine", bin }, {})
          end
          if vim.fn.executable(bin) == 1 then
            vim.notify("[md.nvim] installed → " .. bin)
            cb(bin)
          else
            cb(nil, "bin not executable after extract: " .. bin)
          end
        end)
      end)
    end)
  end)
end

return M
