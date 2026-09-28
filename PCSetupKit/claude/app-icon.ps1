# The app's icon (tray, window, Start menu, desktop): drawn here instead of shipped as a binary, so the kit stays plain
# text. A rounded square with a violet-to-cyan gradient and a white shield with a check (it looks after the PC).
# Every size is drawn on its own grid (sharp at 16 px), stored as PNG frames in one .ico. Prints the path.
# -Png <dir>: also save each size as a .png (to look at it).
param([string]$Path = "$env:USERPROFILE\Documents\Messiah Tray\app.ico", [string]$Png)
$version = 1   # bump when the drawing changes: tray-app.ps1 redraws the icon when this is newer than the file's
Add-Type -AssemblyName System.Drawing

function New-Frame([int]$s) {
    $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([Drawing.Color]::Transparent)
    # rounded square (small sizes use the whole grid: every pixel counts)
    $m = if ($s -le 24) { 0 } else { [Math]::Round($s / 32.0) }
    $w = $s - 2 * $m; $r = $w * 0.26
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($m, $m, 2 * $r, 2 * $r, 180, 90); $p.AddArc($m + $w - 2 * $r, $m, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($m + $w - 2 * $r, $m + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($m, $m + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
    $bg = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF $m, $m), (New-Object Drawing.PointF ($m + $w), ($m + $w)),
        [Drawing.Color]::FromArgb(255, 124, 92, 255), [Drawing.Color]::FromArgb(255, 34, 196, 238))
    $g.FillPath($bg, $p)
    # soft light from the top (depth, Fluent style) - only where it shows
    if ($s -ge 32) {
        $hl = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF 0, ($m - 1)), (New-Object Drawing.PointF 0, ($m + $w + 1)),
            [Drawing.Color]::White, [Drawing.Color]::White)
        $blend = New-Object Drawing.Drawing2D.ColorBlend 3   # fades out by the middle, no hard edge
        $blend.Colors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(60, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255))
        $blend.Positions = [single[]]@(0, 0.55, 1); $hl.InterpolationColors = $blend
        $g.FillPath($hl, $p)
    }
    # shield: flat top with rounded shoulders, sides curving into a point
    $u = $s / 32.0   # drawn on a 32-unit grid
    $cx = $s / 2.0; $top = 7.0 * $u; $half = 8.6 * $u; $mid = 17.0 * $u; $tip = 26.2 * $u
    $sh = New-Object Drawing.Drawing2D.GraphicsPath
    $sh.AddBezier($cx, $top, ($cx + $half * 0.45), ($top + 1.4 * $u), ($cx + $half * 0.8), ($top + 1.3 * $u), ($cx + $half), ($top + 0.9 * $u))
    $sh.AddLine(($cx + $half), ($top + 0.9 * $u), ($cx + $half), $mid - 3 * $u)
    $sh.AddBezier(($cx + $half), ($mid - 3 * $u), ($cx + $half), ($mid + 4.5 * $u), ($cx + 3.5 * $u), ($tip - 1.8 * $u), $cx, $tip)
    $sh.AddBezier($cx, $tip, ($cx - 3.5 * $u), ($tip - 1.8 * $u), ($cx - $half), ($mid + 4.5 * $u), ($cx - $half), ($mid - 3 * $u))
    $sh.AddLine(($cx - $half), ($mid - 3 * $u), ($cx - $half), ($top + 0.9 * $u))
    $sh.AddBezier(($cx - $half), ($top + 0.9 * $u), ($cx - $half * 0.8), ($top + 1.3 * $u), ($cx - $half * 0.45), ($top + 1.4 * $u), $cx, $top)
    $sh.CloseFigure()
    $g.FillPath([Drawing.Brushes]::White, $sh)
    # check mark cut into the shield in the gradient's middle color
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 84, 132, 247)), ([Math]::Max(1.6, 2.6 * $u))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $g.DrawLines($pen, [Drawing.PointF[]]@((New-Object Drawing.PointF ($cx - 4.2 * $u), (16.6 * $u)), (New-Object Drawing.PointF ($cx - 1.2 * $u), (19.6 * $u)), (New-Object Drawing.PointF ($cx + 4.6 * $u), (13.2 * $u))))
    $g.Dispose()
    $bmp
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$frames = foreach ($s in $sizes) {
    $b = New-Frame $s
    if ($Png) { New-Item $Png -ItemType Directory -Force | Out-Null; $b.Save("$Png\icon-$s.png", [Drawing.Imaging.ImageFormat]::Png) }
    $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    , $ms.ToArray()
}
# .ico: header, one directory entry per size, then the PNG data
$out = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $bw.Write($f) }
New-Item (Split-Path $Path) -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllBytes("$Path.tmp", $out.ToArray()); Move-Item "$Path.tmp" $Path -Force
"v$version" | Set-Content "$Path.version" -Encoding ASCII
$Path
