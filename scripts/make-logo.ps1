# 生成 HelloJson App 图标：蓝色圆角底 + 白色花括号 + 下方 “JSON” 字样
# 用法: powershell -ExecutionPolicy Bypass -File .\scripts\make-logo.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$bgPath = Join-Path $root "AppScope\resources\base\media\background.png"
$fgPath = Join-Path $root "AppScope\resources\base\media\foreground.png"
$entryFg = Join-Path $root "entry\src\main\resources\base\media\foreground.png"
$startIcon = Join-Path $root "entry\src\main\resources\base\media\startIcon.png"
$logoPath = Join-Path $root "entry\src\main\resources\base\media\logo.png"

$bgImg = [System.Drawing.Bitmap]::FromFile($bgPath)
$blue = $bgImg.GetPixel(512, 512)
$bgImg.Dispose()

# ---------------- 绘制字形轮廓（精确控制位置与尺寸） ----------------
function Get-GlyphPath([string]$ch, [string]$family, [int]$style, [float]$em) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $ff = New-Object System.Drawing.FontFamily $family
    $p.AddString($ch, $ff, $style, $em, (New-Object System.Drawing.PointF 0, 0), [System.Drawing.StringFormat]::GenericTypographic)
    return $p
}

function Place-Path($path, [float]$targetH, [float]$centerX, [float]$topY) {
    $b = $path.GetBounds()
    if ($b.Height -le 0) { return $null }
    $s = $targetH / $b.Height
    $w = $b.Width * $s
    $m1 = New-Object System.Drawing.Drawing2D.Matrix 1, 0, 0, 1, (-1 * $b.X), (-1 * $b.Y)
    $path.Transform($m1)
    $m2 = New-Object System.Drawing.Drawing2D.Matrix $s, 0, 0, $s, 0, 0
    $path.Transform($m2)
    $m3 = New-Object System.Drawing.Drawing2D.Matrix 1, 0, 0, 1, ($centerX - $w / 2), $topY
    $path.Transform($m3)
    return $w
}

$size = 1024
$canvas = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)

# 花括号：高 470，两个字形间距 96，整体居中
$braceH = 520.0
$braceLeft = Get-GlyphPath '{' 'Segoe UI' 0 1000
$braceRight = Get-GlyphPath '}' 'Segoe UI' 0 1000
$bL = $braceLeft.GetBounds()
$bR = $braceRight.GetBounds()
$sL = $braceH / $bL.Height
$sR = $braceH / $bR.Height

# JSON 文字：字号 118，字距 9
$font = New-Object System.Drawing.Font "Segoe UI", 178.0, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$letters = @('J', 'S', 'O', 'N')
$spacing = 11.0
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$widths = @()
foreach ($c in $letters) {
    $widths += $g.MeasureString($c, $font, 2000, $fmt).Width
}
$textW = ($widths | Measure-Object -Sum).Sum + $spacing * ($letters.Count - 1)
$textH = $font.GetHeight($g)

$gap = 32.0
$totalH = $braceH + $gap + $textH
$topY = ($size - $totalH) / 2

$gapBrace = 172.0
$braceBlockW = ($bL.Width * $sL) + $gapBrace + ($bR.Width * $sR)
$bx = ($size - $braceBlockW) / 2
Place-Path $braceLeft $braceH ($bx + ($bL.Width * $sL) / 2) ([float]$topY) | Out-Null
Place-Path $braceRight $braceH ($bx + ($bL.Width * $sL) + $gapBrace + ($bR.Width * $sR) / 2) ([float]$topY) | Out-Null
$thick = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 13.0
$thick.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$thick.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$thick.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.FillPath($white, $braceLeft)
$g.DrawPath($thick, $braceLeft)
$g.FillPath($white, $braceRight)
$g.DrawPath($thick, $braceRight)

$x = ($size - $textW) / 2
$yText = $topY + $braceH + $gap
for ($i = 0; $i -lt $letters.Count; $i++) {
    $g.DrawString($letters[$i], $font, $white, [float]$x, [float]$yText, $fmt)
    $x += $widths[$i] + $spacing
}

$g.Dispose()
$canvas.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Save($entryFg, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "foreground updated"

function New-Icon([int]$sz, [int]$radius, [string]$outPath) {
    $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gi = [System.Drawing.Graphics]::FromImage($bmp)
    $gi.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gi.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gi.Clear([System.Drawing.Color]::Transparent)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($sz - $d, 0, $d, $d, 270, 90)
    $path.AddArc($sz - $d, $sz - $d, $d, $d, 0, 90)
    $path.AddArc(0, $sz - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $bgBrush = [System.Drawing.SolidBrush]::new($blue)
    $gi.FillPath($bgBrush, $path)
    $gi.SetClip($path)
    $gi.DrawImage($canvas, 0, 0, $sz, $sz)
    $gi.Dispose()
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $outPath"
}

New-Icon 152 34 $startIcon
New-Icon 256 58 $logoPath

$canvas.Dispose()
Write-Host "done"
