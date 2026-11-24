<# : batch section (PowerShell treats this whole block as a comment)
@echo off
setlocal
set "RPCOPY_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:RPCOPY_SELF))"
echo.
pause
exit /b
#>

# ---------------------------------------------------------------------
# RPCopy story exporter
# Reads WTF\Account\*\SavedVariables\RPCopy.lua and writes every saved
# story and adventure to "<WoW folder>\RPCopy Stories\<account>\":
#   <date> - <title>.html      the colored story, readable in a browser
#   <date> - <title>.txt       the story as plain text
#   <date> - <title> - Full Log.txt   the raw Full Log you send to your AI
#   images\<date> - <title>\  the run's screenshots, with ~1280px previews
# plus index.html listing them all. Nothing in the game files is changed.
# Screenshot folder: Options > Stories & Export, or the RPCOPY_SHOTS
# environment variable, or the Screenshots folder next to WTF.
# Tip: the game writes SavedVariables on /reload or logout, so do one of
# those first to export your newest story.
# ---------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$addonDir = Split-Path -Parent $env:RPCOPY_SELF
$wowDir = [IO.Path]::GetFullPath((Join-Path $addonDir '..\..\..'))
$outRoot = Join-Path $wowDir 'RPCopy Stories'
if ($env:RPCOPY_OUT) { $outRoot = $env:RPCOPY_OUT }

# ---------- minimal Lua table reader (enough for WoW SavedVariables) ----------
$tokRe = [regex]'"(?:\\.|[^"\\])*"|--[^\n]*|[\[\]{}=,;]|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[A-Za-z_][A-Za-z0-9_]*'

function Convert-LuaString([string]$raw) {
    $body = $raw.Substring(1, $raw.Length - 2)
    return [regex]::Replace($body, '\\(\d{1,3}|.)', {
        param($m)
        $c = $m.Groups[1].Value
        switch -CaseSensitive ($c) {
            'n' { return "`n" }
            'r' { return "" }
            't' { return "`t" }
            default {
                if ($c -match '^\d+$') { return [string][char][int]$c }
                return $c
            }
        }
    })
}

function Read-LuaValue {
    $t = $script:toks[$script:pos]; $script:pos++
    if ($t -eq '{') {
        $table = [ordered]@{}
        $arrIdx = 1
        while ($script:toks[$script:pos] -ne '}') {
            $tk = $script:toks[$script:pos]
            if ($tk -eq ',' -or $tk -eq ';') { $script:pos++; continue }
            if ($tk -eq '[') {
                $script:pos++
                $key = Read-LuaValue
                $script:pos++   # ]
                $script:pos++   # =
                $table[[string]$key] = Read-LuaValue
            } elseif ($tk -match '^[A-Za-z_]' -and $script:toks[$script:pos + 1] -eq '=') {
                $script:pos += 2
                $table[$tk] = Read-LuaValue
            } else {
                $table[[string]$arrIdx] = Read-LuaValue
                $arrIdx++
            }
        }
        $script:pos++
        return $table
    }
    if ($t.StartsWith('"')) { return Convert-LuaString $t }
    if ($t -eq 'true') { return $true }
    if ($t -eq 'false') { return $false }
    if ($t -eq 'nil') { return $null }
    return [double]$t
}

function Read-SavedVariables([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $script:toks = New-Object System.Collections.Generic.List[string]
    foreach ($m in $tokRe.Matches($text)) {
        if (-not $m.Value.StartsWith('--')) { $script:toks.Add($m.Value) }
    }
    $script:pos = 0
    $globals = @{}
    while ($script:pos -lt $script:toks.Count) {
        $name = $script:toks[$script:pos]
        if ($script:toks[$script:pos + 1] -eq '=') {
            $script:pos += 2
            $globals[$name] = Read-LuaValue
        } else {
            $script:pos++
        }
    }
    return $globals
}

# ---------- WoW color codes -> HTML / plain text ----------
function Get-CleanWowText([string]$s) {
    if (-not $s) { return '' }
    $s = $s.Replace('||', '|')
    $s = [regex]::Replace($s, '\|T.*?\|t', '')
    $s = [regex]::Replace($s, '\|H.*?\|h(.*?)\|h', '$1')
    return $s
}

function ConvertTo-PlainText([string]$s) {
    $s = Get-CleanWowText $s
    $s = [regex]::Replace($s, '\|c[0-9a-fA-F]{8}', '')
    $s = [regex]::Replace($s, '\|cn[^:|]*:', '')
    return $s.Replace('|r', '')
}

function ConvertTo-StoryHtml([string]$s) {
    $s = [Net.WebUtility]::HtmlEncode((Get-CleanWowText $s))
    $sb = New-Object Text.StringBuilder
    $open = 0
    $stack = New-Object System.Collections.ArrayList
    # [Shot N] markers become pictures later: close the open colors around
    # them and reopen them after, so a picture never breaks the coloring
    $parts = [regex]::Split($s, '(\|c[0-9a-fA-F]{8}|\|r|\[[Ss]hot\s*\d+\])')
    foreach ($p in $parts) {
        if ($p -match '^\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})$') {
            [void]$sb.Append('<span style="color:#' + $Matches[1] + '">'); $open++; [void]$stack.Add($Matches[1])
        } elseif ($p -eq '|r') {
            if ($open -gt 0) { [void]$sb.Append('</span>'); $open--; $stack.RemoveAt($stack.Count - 1) }
        } elseif ($p -match '^\[[Ss]hot\s*\d+\]$') {
            for ($k = 0; $k -lt $open; $k++) { [void]$sb.Append('</span>') }
            [void]$sb.Append($p)
            foreach ($c in $stack) { [void]$sb.Append('<span style="color:#' + $c + '">') }
        } else {
            [void]$sb.Append($p)
        }
    }
    while ($open -gt 0) { [void]$sb.Append('</span>'); $open-- }
    return $sb.ToString().Replace("`n", "<br>`n")
}

# Boss icons like the in-game Story reader: a skull (boss), gold dragon
# (elite) or silver dragon (rare) before every recorded boss name, and the
# old orange boss color turned crimson.
function Add-BossIcons([string]$html, $run) {
    $html = [regex]::Replace($html, '(?i)color:#ff8000', 'color:#dc143c')
    $kinds = @{}
    if ($run['bossKills']) { foreach ($v in $run['bossKills'].Values) { $kinds[[string]$v] = 'skull' } }
    if ($run['bossInfo']) {
        foreach ($k in $run['bossInfo'].Keys) {
            $info = $run['bossInfo'][$k]
            $kind = 'skull'
            if ($info -and $info['kind']) { $kind = [string]$info['kind'] }
            $kinds[[string]$k] = $kind
        }
    }
    $names = @($kinds.Keys | Where-Object { $_.Length -ge 3 } | Sort-Object Length -Descending)
    if ($names.Count -eq 0) { return $html }
    $script:bossEnc = @{}
    foreach ($n in $names) { $script:bossEnc[[Net.WebUtility]::HtmlEncode($n)] = $kinds[$n] }
    $alts = ($names | ForEach-Object { [regex]::Escape([Net.WebUtility]::HtmlEncode($_)) }) -join '|'
    $re = New-Object Text.RegularExpressions.Regex ('(?<!\w)(' + $alts + ')(?!\w)')
    return $re.Replace($html, [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $kind = $script:bossEnc[$m.Groups[1].Value]
        $glyph = if ($kind -eq 'skull') { '&#x1F480;' } else { '&#x1F409;' }
        return '<span class="bi bi-' + $kind + '">' + $glyph + '</span>' + $m.Value
    })
}

function Get-SafeFileName([string]$s) {
    $s = [regex]::Replace($s, '[<>:"/\\|?*\x00-\x1f]', '')
    $s = $s.Trim().TrimEnd('.')
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80) }
    if (-not $s) { $s = 'Adventure' }
    return $s
}

$pageStyle = 'body{background:#17120c;color:#eceff1;font-family:Georgia,serif;max-width:860px;margin:32px auto;padding:0 16px;line-height:1.65}' +
    'h1{color:#ffd100;font-size:22px}a{color:#69ccf0}.meta{color:#9e9e9e;font-size:13px}' +
    '.story{background:#1f1810;border:1px solid #8a6d33;border-radius:6px;padding:20px 24px}' +
    '.bi{font-size:0.9em;margin-right:3px}.bi-elite{filter:sepia(1) saturate(5) hue-rotate(-12deg) brightness(1.1)}.bi-rare{filter:grayscale(1) brightness(1.4)}'

# ---------- screenshots (0.5.0) ----------
# WoW names shots WoWScrnShot_MMDDYY_HHMMSS.jpg in local time, the same
# clock as RPCopy's run times. A run's shots are the files between its
# start (minus 30s) and its end (plus 2 minutes). Shots RPCopy recorded
# (auto shots, and your own Print Screen shots during a run) carry a
# number and a caption; the story's [Shot N] markers place them.
function Get-ShotFiles([string]$dir) {
    $list = New-Object System.Collections.ArrayList
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return ,$list }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^WoWScrnShot_(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.(jpg|jpeg|png)$') {
            try {
                $when = New-Object DateTime -ArgumentList (2000 + [int]$Matches[3]), ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[4]), ([int]$Matches[5]), ([int]$Matches[6])
                [void]$list.Add([pscustomobject]@{ Path = $f.FullName; Name = $f.Name; When = $when; Size = $f.Length })
            } catch { }
        }
    }
    return ,$list
}

function ConvertFrom-LuaTime($t) {
    if (-not $t) { return $null }
    try { return [DateTimeOffset]::FromUnixTimeSeconds([long][double]$t).LocalDateTime } catch { return $null }
}

$script:drawingReady = $null
function Save-Preview([string]$src, [string]$dst, [int]$maxW) {
    if ($script:drawingReady -eq $null) {
        try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop; $script:drawingReady = $true } catch { $script:drawingReady = $false }
    }
    if (-not $script:drawingReady) { return $false }
    try {
        $img = [System.Drawing.Image]::FromFile($src)
        try {
            if ($img.Width -le $maxW) { Copy-Item -LiteralPath $src -Destination $dst -Force; return $true }
            $h = [int]($img.Height * $maxW / $img.Width)
            $bmp = New-Object System.Drawing.Bitmap -ArgumentList $maxW, $h
            $gr = [System.Drawing.Graphics]::FromImage($bmp)
            $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gr.DrawImage($img, 0, 0, $maxW, $h)
            $gr.Dispose()
            $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
            $ep = New-Object System.Drawing.Imaging.EncoderParameters -ArgumentList 1
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter -ArgumentList ([System.Drawing.Imaging.Encoder]::Quality), ([long]82)
            $bmp.Save($dst, $codec, $ep)
            $bmp.Dispose()
        } finally { $img.Dispose() }
        return $true
    } catch { return $false }
}

# A path the page can use: relative when the images sit under the page folder
function Get-ImageRef([string]$file, [string]$pageDir) {
    $full = [IO.Path]::GetFullPath($file)
    $root = [IO.Path]::GetFullPath($pageDir).TrimEnd('\') + '\'
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($root.Length).Replace('\', '/')
        return (($rel -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    }
    return ([Uri]$full).AbsoluteUri
}

function Get-Figure($shot) {
    $cap = ''
    if ($shot.Caption) { $cap = '<figcaption>' + [Net.WebUtility]::HtmlEncode($shot.Caption) + '</figcaption>' }
    return '<figure class="shot"><a href="' + $shot.FullRef + '"><img src="' + $shot.PrevRef + '" alt="screenshot" loading="lazy"></a>' + $cap + '</figure>'
}

# Copies a story's shots next to the page and returns them in time order
function Get-StoryShots($st, $files, [string]$imgRoot, [string]$base, [string]$pageDir) {
    $out = New-Object System.Collections.ArrayList
    $start = ConvertFrom-LuaTime $st['startTime']
    if (-not $start) { return $out }
    $endT = $st['endTime']
    if (-not $endT -and $st['duration'] -and [double]$st['duration'] -gt 0) { $endT = [double]$st['startTime'] + [double]$st['duration'] }
    if (-not $endT) { $endT = $st['lastSeen'] }
    $end = ConvertFrom-LuaTime $endT
    if (-not $end) { $end = $start.AddHours(6) }
    $from = $start.AddSeconds(-30); $to = $end.AddMinutes(2)
    $recorded = @()
    if ($st['shots']) {
        foreach ($k in $st['shots'].Keys) {
            $sh = $st['shots'][$k]
            if ($sh -is [System.Collections.IDictionary] -and $sh['at']) {
                $recorded += [pscustomobject]@{ N = [int]$(if ($sh['n']) { $sh['n'] } else { $k }); When = (ConvertFrom-LuaTime $sh['at']); Caption = [string]$sh['description']; Used = $false }
            }
        }
    }
    $dir = Join-Path $imgRoot $base
    foreach ($f in ($files | Where-Object { $_.When -ge $from -and $_.When -le $to } | Sort-Object When)) {
        $n = $null; $cap = ''
        foreach ($r in $recorded) {
            if (-not $r.Used -and $r.When -and [Math]::Abs(($r.When - $f.When).TotalSeconds) -le 3) { $r.Used = $true; $n = $r.N; $cap = $r.Caption; break }
        }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = Join-Path $dir $f.Name
        if (-not (Test-Path -LiteralPath $full) -or (Get-Item -LiteralPath $full).Length -ne $f.Size) {
            Copy-Item -LiteralPath $f.Path -Destination $full -Force
        }
        $prev = Join-Path $dir ('preview_' + [IO.Path]::GetFileNameWithoutExtension($f.Name) + '.jpg')
        if (-not (Test-Path -LiteralPath $prev)) {
            if (-not (Save-Preview $full $prev 1280)) { $prev = $full }
        }
        [void]$out.Add([pscustomobject]@{ N = $n; When = $f.When; Caption = $cap; FullRef = (Get-ImageRef $full $pageDir); PrevRef = (Get-ImageRef $prev $pageDir); Placed = $false })
    }
    return $out
}

# Puts the shots into the story: [Shot N] markers first, then a chapter
# whose title the caption names, then by time across the chapters, and
# whatever is left in a gallery at the end
function Add-StoryShots([string]$html, $shots, $st) {
    $script:shotByN = @{}
    foreach ($s in $shots) { if ($s.N) { $script:shotByN[[string]$s.N] = $s } }
    $html = [regex]::Replace($html, '\[[Ss]hot\s*(\d+)\]', {
        param($m)
        $s = $script:shotByN[$m.Groups[1].Value]
        if ($s -and -not $s.Placed) { $s.Placed = $true; return (Get-Figure $s) }
        return ''
    })
    $left = @($shots | Where-Object { -not $_.Placed })
    if ($left.Count -eq 0) { return $html }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in ($html -split "<br>`n")) { [void]$lines.Add($l) }
    $chapters = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $plain = [regex]::Replace([string]$lines[$i], '<[^>]+>', '')
        if ($plain -match '^\s*Chapter\s+\w+\s*:?\s*(.*)$') { $chapters += [pscustomobject]@{ Line = $i; Title = $Matches[1].Trim(); Extra = (New-Object System.Collections.ArrayList) } }
    }
    $gallery = New-Object System.Collections.ArrayList
    if ($chapters.Count -eq 0) {
        foreach ($s in $left) { [void]$gallery.Add($s) }
    } else {
        $start = ConvertFrom-LuaTime $st['startTime']
        $spanSec = [double]$(if ($st['duration']) { $st['duration'] } else { 0 })
        foreach ($s in $left) {
            $target = $null
            if ($s.Caption) {
                foreach ($c in $chapters) {
                    $words = @($c.Title -split '[^\w'']+' | Where-Object { $_.Length -ge 5 })
                    foreach ($w in $words) { if ($s.Caption.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $target = $c; break } }
                    if ($target) { break }
                }
            }
            if (-not $target -and $start -and $spanSec -gt 0) {
                $frac = ($s.When - $start).TotalSeconds / $spanSec
                $idx = [int][Math]::Floor([Math]::Max(0, [Math]::Min(0.999, $frac)) * $chapters.Count)
                $target = $chapters[$idx]
            }
            if ($target) { [void]$target.Extra.Add($s) } else { [void]$gallery.Add($s) }
        }
        # each chapter's shots go at its end (just before the next chapter)
        for ($ci = $chapters.Count - 1; $ci -ge 0; $ci--) {
            $c = $chapters[$ci]
            if ($c.Extra.Count -eq 0) { continue }
            $at = if ($ci + 1 -lt $chapters.Count) { $chapters[$ci + 1].Line } else { $lines.Count }
            $figs = ($c.Extra | ForEach-Object { Get-Figure $_ }) -join ''
            $lines.Insert($at, $figs)
        }
    }
    $html = ($lines -join "<br>`n")
    if ($gallery.Count -gt 0) {
        $html += '<div class="gallery">' + (($gallery | ForEach-Object { Get-Figure $_ }) -join '') + '</div>'
    }
    return $html
}

# ---------- export ----------
$svFiles = @(Get-ChildItem -Path (Join-Path $wowDir 'WTF\Account\*\SavedVariables\RPCopy.lua') -ErrorAction SilentlyContinue)
if ($svFiles.Count -eq 0) {
    Write-Host "No RPCopy SavedVariables found under $wowDir\WTF."
    Write-Host 'Log in with RPCopy enabled, then /reload or log out once, and run this again.'
    exit
}

$pageStyle += 'figure.shot{margin:16px 0;text-align:center}figure.shot img{max-width:100%;border:1px solid #8a6d33;border-radius:4px}' +
    'figcaption{color:#b0a080;font-size:13px;font-style:italic;margin-top:4px}.gallery{margin-top:24px;border-top:1px solid #8a6d33;padding-top:8px}' +
    '.cover{width:160px;height:90px;object-fit:cover;border:1px solid #8a6d33;border-radius:4px;vertical-align:middle;margin-right:10px}' +
    'li{margin:8px 0;list-style:none}'

$total = 0
foreach ($sv in $svFiles) {
    $account = Get-SafeFileName $sv.Directory.Parent.Name
    Write-Host "Reading $($sv.FullName)"
    try {
        $g = Read-SavedVariables $sv.FullName
    } catch {
        Write-Host "  Could not read this file: $($_.Exception.Message)"
        continue
    }
    $db = $g['RPCopyDB']
    if (-not $db) { Write-Host '  No RPCopyDB in this file.'; continue }

    # Where the game's screenshots are: RPCOPY_SHOTS, then Options > Stories
    # & Export, then the Screenshots folder of this WoW install
    $shotDir = Join-Path $wowDir 'Screenshots'
    if ($db['exportShotsDir']) { $shotDir = [string]$db['exportShotsDir'] }
    if ($env:RPCOPY_SHOTS) { $shotDir = $env:RPCOPY_SHOTS }
    $shotFiles = Get-ShotFiles $shotDir

    $outDir = Join-Path $outRoot $account
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $imgRoot = Join-Path $outDir 'images'
    if ($db['exportImageDir']) { $imgRoot = [string]$db['exportImageDir'] }

    # 0.5.0: stories live in RPCopyDB.stories, apart from the recordings.
    # Older saves keep the story inside the run; both are read.
    $runs = New-Object System.Collections.ArrayList
    if ($db['activeRun']) { [void]$runs.Add($db['activeRun']) }
    if ($db['adventures']) { foreach ($k in $db['adventures'].Keys) { [void]$runs.Add($db['adventures'][$k]) } }
    $runById = @{}
    foreach ($r in $runs) { if ($r['id']) { $runById[[string]$r['id']] = $r } }
    $items = New-Object System.Collections.ArrayList
    $storyRuns = @{}
    if ($db['stories']) {
        foreach ($k in $db['stories'].Keys) {
            $st = $db['stories'][$k]
            if ($st['story']) {
                $run = $null
                if ($st['runId'] -and $runById.ContainsKey([string]$st['runId'])) { $run = $runById[[string]$st['runId']]; $storyRuns[[string]$st['runId']] = $true }
                [void]$items.Add([pscustomobject]@{ Meta = $st; Story = [string]$st['story']; Run = $run })
            }
        }
    }
    foreach ($r in $runs) {
        if ($r['id'] -and $storyRuns.ContainsKey([string]$r['id'])) { continue }
        [void]$items.Add([pscustomobject]@{ Meta = $r; Story = [string]$r['story']; Run = $r })
    }
    if ($items.Count -eq 0) { Write-Host '  No adventures or stories saved yet.'; continue }

    $index = New-Object Text.StringBuilder
    [void]$index.Append("<!doctype html><html><head><meta charset=""utf-8""><title>RPCopy Stories</title><style>$pageStyle</style></head><body><h1>RPCopy Stories</h1><ul>")

    $used = @{}
    $shotCount = 0
    foreach ($it in $items) {
        $meta = $it.Meta
        $title = if ($meta['book'] -and $meta['book']['title']) { [string]$meta['book']['title'] } elseif ($meta['title']) { [string]$meta['title'] } else { 'Adventure' }
        $date = if ($meta['startDate']) { ([string]$meta['startDate']).Replace(':', '') } else { 'undated' }
        $base = Get-SafeFileName "$date - $title"
        if ($used.ContainsKey($base)) { $used[$base]++; $base = "$base ($($used[$base]))" } else { $used[$base] = 1 }

        $story = $it.Story
        $log = ''
        if ($it.Run) {
            $log = [string]$it.Run['exportText']
            if (-not $log -and $it.Run['fullTimeline']) { $log = ($it.Run['fullTimeline'].Values -join "`r`n") }
        }
        $isLive = $it.Run -and [object]::ReferenceEquals($it.Run, $db['activeRun'])

        $links = @()
        $cover = ''
        if ($story) {
            $shots = @()
            try { $shots = @(Get-StoryShots $meta $shotFiles $imgRoot $base $outDir) } catch { Write-Host "  Screenshots skipped for $title : $($_.Exception.Message)" }
            $shotCount += $shots.Count
            $storyHtml = Add-BossIcons (ConvertTo-StoryHtml $story) $meta
            if ($shots.Count -gt 0) { $storyHtml = Add-StoryShots $storyHtml $shots $meta; $cover = '<img class="cover" src="' + $shots[0].PrevRef + '" alt="">' }
            $storyHtml = [regex]::Replace($storyHtml, '\[[Ss]hot\s*\d+\]', '')
            $page = "<!doctype html><html><head><meta charset=""utf-8""><title>$([Net.WebUtility]::HtmlEncode($title))</title><style>$pageStyle</style></head><body>" +
                "<p><a href=""index.html"">&larr; all stories</a></p>" +
                "<h1>$([Net.WebUtility]::HtmlEncode($title))</h1><p class=""meta"">$([Net.WebUtility]::HtmlEncode([string]$meta['zone'])) - $([Net.WebUtility]::HtmlEncode([string]$meta['startDate']))</p>" +
                "<div class=""story"">$storyHtml</div></body></html>"
            [IO.File]::WriteAllText((Join-Path $outDir "$base.html"), $page, (New-Object Text.UTF8Encoding $false))
            $plain = [regex]::Replace((ConvertTo-PlainText $story), '\s*\[[Ss]hot\s*\d+\]', '')
            [IO.File]::WriteAllText((Join-Path $outDir "$base.txt"), ($plain -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $false))
            $links += "<a href=""$([Uri]::EscapeDataString("$base.html"))"">story</a>"
        }
        if ($log) {
            [IO.File]::WriteAllText((Join-Path $outDir "$base - Full Log.txt"), ((ConvertTo-PlainText $log) -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $false))
            $links += "<a href=""$([Uri]::EscapeDataString("$base - Full Log.txt"))"">full log</a>"
        }
        $liveTag = if ($isLive) { ' (live run)' } else { '' }
        $noStory = if ($story) { '' } else { ' <span class="meta">no story imported yet</span>' }
        $gone = if ($story -and -not $it.Run) { ' <span class="meta">(recording deleted, story kept)</span>' } else { '' }
        [void]$index.Append("<li>$cover$([Net.WebUtility]::HtmlEncode("$date - $title"))$liveTag : $($links -join ' | ')$noStory$gone</li>")
        $total++
    }
    [void]$index.Append('</ul></body></html>')
    [IO.File]::WriteAllText((Join-Path $outDir 'index.html'), $index.ToString(), (New-Object Text.UTF8Encoding $false))
    Write-Host "  Exported $($items.Count) item(s) with $shotCount screenshot(s) to $outDir"
    if ($shotFiles.Count -eq 0) { Write-Host "  (No screenshots found in $shotDir. Set the folder in Options > Stories & Export, or set RPCOPY_SHOTS.)" }
}

if ($total -gt 0 -and -not $env:RPCOPY_NOOPEN) {
    Write-Host ''
    Write-Host "Done. Opening $outRoot"
    Start-Process explorer.exe -ArgumentList "`"$outRoot`""
}
