# Call of Duty's own benchmark (Settings > Graphics > Benchmark, 10/23): each run writes a CSV to
# %LOCALAPPDATA%\Activision\Call of Duty\players\performance_results. This lists the runs - the same scripted scene
# every time, so unlike match samples (game-perf.ps1) a map or mode can't skew a before/after comparison.
# -Last N: only the newest N runs. -Since: runs after this time. -Json: objects instead of a table.
param([int]$Last = 0, [datetime]$Since = [datetime]::MinValue, [switch]$Json,
    [string]$Dir = "$env:LOCALAPPDATA\Activision\Call of Duty\players\performance_results")
$ErrorActionPreference = 'SilentlyContinue'
$runs = foreach ($f in Get-ChildItem $Dir -Filter '*Benchmark*.csv' | Sort-Object LastWriteTime) {
    if ($f.LastWriteTime -lt $Since) { continue }
    $hd = @{}; $m = @{}
    foreach ($l in [IO.File]::ReadLines($f.FullName)) {
        if ($l -match '^# ([^,]+?):?,\s*(.*)$') { $hd[$Matches[1].Trim()] = $Matches[2].Trim() }
        elseif ($l -match '^([^#,][^,]*),(-?[\d.]+),') { $m[$Matches[1]] = [double]$Matches[2] }
        elseif ($l -match '^# CPU Times') { break }
    }
    [pscustomobject][ordered]@{
        time = $f.LastWriteTime.ToString('MM-dd HH:mm'); fps = $m['Global Average FPS']; low1 = $m['Global Low 1th FPS']; low5 = $m['Global Low 5th FPS']
        cpuFps = $m['Cpu Average FPS']; gpuFps = $m['Gpu Average FPS']; gpuBound = $m['Gpu Bottleneck (%)']; latency = $m['Input Latency Average MS']
        hitches = $m['PagingHitch  times']; render = $hd['Render Resolution']; upscale = $hd['Upscaling/Sharpening']; cap = $hd['Framerate Limit']
        frameGen = [bool]($m['GlobalFrameGen Average FPS'] -and $m['GlobalFrameGen Average FPS'] -ne $m['Global Average FPS']); driver = $hd['Gpu Driver']; file = $f.Name
    }
}
if ($Last -gt 0) { $runs = @($runs) | Select-Object -Last $Last }
if ($Json) { $runs } else { $runs | Format-Table time, fps, low1, low5, cpuFps, gpuFps, gpuBound, latency, hitches, render, upscale, cap -AutoSize | Out-String -Width 250 }
