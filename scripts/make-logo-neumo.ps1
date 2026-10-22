# 把 AI 生成的新拟态图标转换为 App 图标资源
# 用法: powershell -ExecutionPolicy Bypass -File .\scripts\make-logo-neumo.ps1 -Source "<png路径>"
param(
    [Parameter(Mandatory = $true)][string]$Source
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appBg = Join-Path $root "AppScope\resources\base\media\background.png"
$appFg = Join-Path $root "AppScope\resources\base\media\foreground.png"
$entryBg = Join-Path $root "entry\src\main\resources\base\media\background.png"
$entryFg = Join-Path $root "entry\src\main\resources\base\media\foreground.png"
$startIcon = Join-Path $root "entry\src\main\resources\base\media\startIcon.png"
$logoPath = Join-Path $root "entry\src\main\resources\base\media\logo.png"

# 备份
$bak = Join-Path $root "build-output\icon-backup"
New-Item -ItemType Directory -Force -Path $bak | Out-Null
foreach ($p in @($appBg, $appFg, $startIcon, $logoPath)) {
    if (Test-Path $p) {
        Copy-Item $p (Join-Path $bak ((Split-Path $p -Parent).Replace($root, '').Replace('\', '_').Replace(':', '') + '_' + (Split-Path $p -Leaf))) -Force
    }
}

$srcFile = [System.Drawing.Bitmap]::FromFile($Source)
$src = New-Object System.Drawing.Bitmap $srcFile
$srcFile.Dispose()

# 裁掉外圈背景（含右下角水印），只保留圆角方块本体
$crop = New-Object System.Drawing.Rectangle 100, 96, 820, 820
$baseBmp = New-Object System.Drawing.Bitmap 1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($baseBmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 1024, 1024), $crop, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()

# 采样方块主色（用于圆角外填充）
$plate = $baseBmp.GetPixel(40, 512)

function New-Rounded([System.Drawing.Bitmap]$img, [int]$sz, [int]$radius) {
    $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gi = [System.Drawing.Graphics]::FromImage($bmp)
    $gi.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gi.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gi.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($sz - $d, 0, $d, $d, 270, 90)
    $path.AddArc($sz - $d, $sz - $d, $d, $d, 0, 90)
    $path.AddArc(0, $sz - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $gi.FillPath((New-Object System.Drawing.SolidBrush $plate), $path)
    $gi.SetClip($path)
    $gi.DrawImage($img, 0, 0, $sz, $sz)
    $gi.Dispose()
    return $bmp
}

$icon1024 = New-Rounded $baseBmp 1024 240
$icon152 = New-Rounded $baseBmp 152 36
$icon256 = New-Rounded $baseBmp 256 60

# background = 完整图标，foreground = 全透明（新拟态效果已烘进底图）
$icon1024.Save($appBg, [System.Drawing.Imaging.ImageFormat]::Png)
$icon1024.Save($entryBg, [System.Drawing.Imaging.ImageFormat]::Png)
$blank2 = New-Object System.Drawing.Bitmap 1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$blank2.Save($appFg, [System.Drawing.Imaging.ImageFormat]::Png)
$blank2.Save($entryFg, [System.Drawing.Imaging.ImageFormat]::Png)
$icon152.Save($startIcon, [System.Drawing.Imaging.ImageFormat]::Png)
$icon256.Save($logoPath, [System.Drawing.Imaging.ImageFormat]::Png)

$icon1024.Dispose()
$icon152.Dispose()
$icon256.Dispose()
$blank2.Dispose()
$baseBmp.Dispose()
$src.Dispose()
Write-Host "neumorphic icon applied (plate color: $($plate.ToString()))"
