# The app's icon (tray, window, Start menu, desktop): drawn here instead of shipped as a binary, so the kit stays plain
# text. A dark rounded tile with a bold geometric M in a violet-to-cyan gradient under a thin halo (v2, 10/2; v1 was a shield).
# Every size is drawn on its own grid (sharp at 16 px), stored as PNG frames in one .ico. Prints the path.
# -Png <dir>: also save each size as a .png (to look at it).
param([string]$Path = "$env:USERPROFILE\Documents\Messiah Tray\app.ico", [string]$Png)
$version = 2   # bump when the drawing changes: tray-app.ps1 redraws the icon when this is newer than the file's
Add-Type -AssemblyName System.Drawing

function New-Frame([int]$s) {
    $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([Drawing.Color]::Transparent)
    $u = $s / 32.0   # drawn on a 32-unit grid
    $violet = [Drawing.Color]::FromArgb(255, 139, 92, 255); $cyan = [Drawing.Color]::FromArgb(255, 34, 211, 238)
    # the tile: dark, almost black, a little violet at the top (small sizes use the whole grid: every pixel counts)
    $m = if ($s -le 24) { 0 } else { [Math]::Round($s / 32.0) }
    $w = $s - 2 * $m; $r = $w * 0.25
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($m, $m, 2 * $r, 2 * $r, 180, 90); $p.AddArc($m + $w - 2 * $r, $m, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($m + $w - 2 * $r, $m + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($m, $m + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
    $bg = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF 0, $m), (New-Object Drawing.PointF 0, ($m + $w)),
        [Drawing.Color]::FromArgb(255, 30, 22, 58), [Drawing.Color]::FromArgb(255, 9, 9, 16))
    $g.FillPath($bg, $p)
    # a hairline rim in the gradient (where there's room): the tile stays visible on a dark taskbar
    if ($s -ge 32) {
        $rim = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF $m, $m), (New-Object Drawing.PointF ($m + $w), ($m + $w)),
            [Drawing.Color]::FromArgb(150, $violet), [Drawing.Color]::FromArgb(150, $cyan))
        $g.DrawPath((New-Object Drawing.Pen $rim, ([Math]::Max(1.0, 0.7 * $u))), $p)
    }
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF (6 * $u), (8 * $u)), (New-Object Drawing.PointF (26 * $u), (26 * $u)), $violet, $cyan)
    # the M: two peaks, mitred - bigger at 16-20 px, where the halo has no room
    $small = $s -le 20
    $y0 = if ($small) { 8.0 } else { 12.2 }; $y1 = if ($small) { 25.0 } else { 24.6 }; $vy = if ($small) { 18.2 } else { 19.6 }
    $x0 = if ($small) { 6.0 } else { 7.4 }; $x1 = 32 - $x0
    $pts = [Drawing.PointF[]]@((New-Object Drawing.PointF ($x0 * $u), ($y1 * $u)), (New-Object Drawing.PointF ($x0 * $u), ($y0 * $u)),
        (New-Object Drawing.PointF (16 * $u), ($vy * $u)), (New-Object Drawing.PointF ($x1 * $u), ($y0 * $u)), (New-Object Drawing.PointF ($x1 * $u), ($y1 * $u)))
    $mw = if ($small) { 4.2 * $u } else { 3.5 * $u }
    if ($s -ge 40) {   # a soft light behind it (a radial fade - no edges)
        $gl = New-Object Drawing.Drawing2D.GraphicsPath; $gl.AddEllipse((3 * $u), (9 * $u), (26 * $u), (19 * $u))
        $rb = New-Object Drawing.Drawing2D.PathGradientBrush $gl; $rb.CenterColor = [Drawing.Color]::FromArgb(70, 99, 102, 241); $rb.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 99, 102, 241))
        $g.SetClip($p); $g.FillPath($rb, $gl); $g.ResetClip()
    }
    $pen = New-Object Drawing.Pen $grad, $mw; $pen.LineJoin = 'Miter'; $pen.MiterLimit = 3; $pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'
    $g.DrawLines($pen, $pts)
    # the halo above it
    if (-not $small) {
        $hx = 9.6 * $u; $hy = 4.4 * $u; $hw = 12.8 * $u; $hh = 3.8 * $u
        $hp = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.PointF $hx, 0), (New-Object Drawing.PointF ($hx + $hw), 0), $cyan, $violet)
        $g.DrawEllipse((New-Object Drawing.Pen $hp, ([Math]::Max(1.1, 1.15 * $u))), $hx, $hy, $hw, $hh)
    }
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
