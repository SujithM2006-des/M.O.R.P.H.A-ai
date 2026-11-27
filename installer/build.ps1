# Builds the M.O.R.P.H.A. setup file:  MORPHA-Setup-<version>.exe
#
#   powershell -ExecutionPolicy Bypass -File installer\build.ps1 [-Version 2.0.0] [-Out <folder>]
#
# Nothing in the project or in ~/.jarvis is changed. Only git-tracked files
# (plus this installer folder) are copied to a temporary staging folder, so
# secrets and personal files - .env.local, your own look, test leftovers - can
# never end up in the setup. The icon and the wizard pictures are drawn
# there, Inno Setup compiles installer\jarvis.iss, and the staging folder is
# deleted again. Needs Inno Setup 6:  winget install JRSoftware.InnoSetup --scope user

param(
  [string]$Version = '2.0.0',
  [string]$Out = (Join-Path $env:USERPROFILE 'Downloads\jarvis final')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $env:TEMP 'jarvis-setup-build'
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is not installed. Run:  winget install JRSoftware.InnoSetup --scope user' }

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'app'), $Out | Out-Null

# --- the app: tracked files only ---------------------------------------------
$files = @(git -C $repo ls-files) + @(git -C $repo ls-files --others --exclude-standard -- installer) | Sort-Object -Unique
# Not for users: the developer's tool settings, the test suite, the bug log.
$skip = '^(\.claude/|test/|\.oxlintrc\.json$|BUG-REPORT\.md$|installer/build\.ps1$|scripts/try-ollama\.mjs$)'
$count = 0
foreach ($f in $files) {
  if ($f -match $skip) { continue }
  $src = Join-Path $repo $f
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
  $dst = Join-Path (Join-Path $stage 'app') $f
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst
  $count++
}
# Belt and braces: these must never be shipped.
foreach ($bad in '.env.local', '.env', 'src\custom\CustomLayout.tsx', 'src\custom\custom-layout.css', 'src\custom\user-theme.css', 'scripts\try-ollama.mjs', 'node_modules') {
  if (Test-Path (Join-Path (Join-Path $stage 'app') $bad)) { throw "Refusing to package $bad" }
}
Write-Host "staged $count files"

# --- the icon and the wizard pictures ------------------------------------------
Add-Type -AssemblyName System.Drawing
$accent = [System.Drawing.ColorTranslator]::FromHtml('#19d8d2')
$navy = [System.Drawing.Color]::FromArgb(255, 4, 14, 28)

function Draw-Reactor($g, [float]$cx, [float]$cy, [float]$r) {
  $g.SmoothingMode = 'AntiAlias'
  foreach ($w in 0.30, 0.20, 0.11) {
    $glow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(45, $accent.R, $accent.G, $accent.B)), ($r * $w)
    $g.DrawEllipse($glow, $cx - $r * 0.78, $cy - $r * 0.78, $r * 1.56, $r * 1.56)
  }
  $g.DrawEllipse((New-Object System.Drawing.Pen $accent, ($r * 0.09)), $cx - $r * 0.78, $cy - $r * 0.78, $r * 1.56, $r * 1.56)
  $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, $accent.R, $accent.G, $accent.B)), ($r * 0.03)), $cx - $r * 0.5, $cy - $r * 0.5, $r, $r)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $accent), $cx - $r * 0.22, $cy - $r * 0.22, $r * 0.44, $r * 0.44)
}

# The M.O.R.P.H.A. logo (public\brand): the round M for icons, the badge with
# the name for the wizard's big picture.
$markImg = [System.Drawing.Image]::FromFile((Join-Path $repo 'public\brand\morpha-mark.png'))
$logoImg = [System.Drawing.Image]::FromFile((Join-Path $repo 'public\brand\morpha-logo.png'))
function Draw-Scaled($g, $img, [float]$x, [float]$y, [float]$w, [float]$h) {
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($img, $x, $y, $w, $h)
}

function Png([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Transparent)
  Draw-Scaled $g $markImg 0 0 $size $size
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return , $ms.ToArray()
}

# A multi-size .ico (PNG frames: sharp from the taskbar to the Start menu tiles).
$sizes = 256, 64, 48, 32, 16
$frames = foreach ($s in $sizes) { , (Png $s) }
$fs = [System.IO.File]::Create((Join-Path $stage 'jarvis.ico'))
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $len = $frames[$i].Length
  $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s }))); $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
  $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
  $offset += $len
}
foreach ($fr in $frames) { $bw.Write($fr) }
$bw.Close()

function Wizard-Bitmap([int]$w, [int]$h, [string]$path, [bool]$big) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 6, 22, 44)), $navy, 90
  $g.FillRectangle($bg, $rect)
  if ($big) {
    # The badge (the M and the word MORPHA), then the name and the credit.
    # Clipped to a circle: the picture's square corners do not match this background.
    $side = $w * 0.94
    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse([float](($w - $side) / 2 + $side * 0.015), [float]($h * 0.16 + $side * 0.015), [float]($side * 0.97), [float]($side * 0.97))
    $g.SetClip($clip)
    Draw-Scaled $g $logoImg (($w - $side) / 2) ($h * 0.16) $side $side
    $g.ResetClip()
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'
    $g.DrawString('M.O.R.P.H.A.', (New-Object System.Drawing.Font 'Segoe UI Semibold', ([float]($w * 0.085))), (New-Object System.Drawing.SolidBrush $accent), (New-Object System.Drawing.RectangleF 0, ($h * 0.68), $w, ($h * 0.1)), $fmt)
    $g.DrawString('Personal AI Assistant', (New-Object System.Drawing.Font 'Segoe UI', ([float]($w * 0.052))), (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 200, 225, 240))), (New-Object System.Drawing.RectangleF 0, ($h * 0.76), $w, ($h * 0.06)), $fmt)
    $g.DrawString('(C) 2026 Sujith M', (New-Object System.Drawing.Font 'Segoe UI', ([float]($w * 0.045))), (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 160, 190, 210))), (New-Object System.Drawing.RectangleF 0, ($h * 0.92), $w, ($h * 0.05)), $fmt)
  } else {
    Draw-Scaled $g $markImg ($w * 0.04) ($h * 0.04) ($w * 0.92) ($h * 0.92)
  }
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
  $bmp.Dispose()
}
# Twice the standard sizes, so they stay crisp on high-DPI screens.
Wizard-Bitmap 328 628 (Join-Path $stage 'wizard.bmp') $true
Wizard-Bitmap 110 110 (Join-Path $stage 'wizard-small.bmp') $false
$markImg.Dispose(); $logoImg.Dispose()

# --- compile ------------------------------------------------------------------
& $iscc /Q "/DAppVersion=$Version" "/DStage=$stage" "/DOutDir=$Out" (Join-Path $PSScriptRoot 'jarvis.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed on the setup (exit $LASTEXITCODE)" }
# The standalone uninstaller, to share next to the setup file.
& $iscc /Q "/DAppVersion=$Version" "/DStage=$stage" "/DOutDir=$Out" (Join-Path $PSScriptRoot 'uninstaller.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed on the uninstaller (exit $LASTEXITCODE)" }
Remove-Item $stage -Recurse -Force
foreach ($name in "MORPHA-Setup-$Version.exe", 'MORPHA-Uninstall.exe') {
  $exe = Get-Item (Join-Path $Out $name)
  Write-Host ("built {0} ({1:N1} MB)" -f $exe.FullName, ($exe.Length / 1MB))
}
