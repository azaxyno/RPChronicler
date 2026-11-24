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
# adventure to "<WoW folder>\RPCopy Stories\<account>\":
#   <date> - <title>.html      the colored story, readable in a browser
#   <date> - <title>.txt       the story as plain text
#   <date> - <title> - Full Log.txt   the raw Full Log you send to your AI
# plus index.html listing them all. Nothing in the game files is changed.
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
    $parts = [regex]::Split($s, '(\|c[0-9a-fA-F]{8}|\|r)')
    foreach ($p in $parts) {
        if ($p -match '^\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})$') {
            [void]$sb.Append('<span style="color:#' + $Matches[1] + '">'); $open++
        } elseif ($p -eq '|r') {
            if ($open -gt 0) { [void]$sb.Append('</span>'); $open-- }
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

# ---------- export ----------
$svFiles = @(Get-ChildItem -Path (Join-Path $wowDir 'WTF\Account\*\SavedVariables\RPCopy.lua') -ErrorAction SilentlyContinue)
if ($svFiles.Count -eq 0) {
    Write-Host "No RPCopy SavedVariables found under $wowDir\WTF."
    Write-Host 'Log in with RPCopy enabled, then /reload or log out once, and run this again.'
    exit
}

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

    $runs = New-Object System.Collections.ArrayList
    if ($db['activeRun']) { [void]$runs.Add($db['activeRun']) }
    if ($db['adventures']) { foreach ($k in $db['adventures'].Keys) { [void]$runs.Add($db['adventures'][$k]) } }
    if ($runs.Count -eq 0) { Write-Host '  No adventures saved yet.'; continue }

    $outDir = Join-Path $outRoot $account
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $index = New-Object Text.StringBuilder
    [void]$index.Append("<!doctype html><html><head><meta charset=""utf-8""><title>RPCopy Stories</title><style>$pageStyle</style></head><body><h1>RPCopy Stories</h1><ul>")

    $used = @{}
    foreach ($run in $runs) {
        $title = if ($run['title']) { [string]$run['title'] } else { 'Adventure' }
        $date = if ($run['startDate']) { ([string]$run['startDate']).Replace(':', '') } else { 'undated' }
        $base = Get-SafeFileName "$date - $title"
        if ($used.ContainsKey($base)) { $used[$base]++; $base = "$base ($($used[$base]))" } else { $used[$base] = 1 }

        $story = [string]$run['story']
        $log = [string]$run['exportText']
        if (-not $log -and $run['fullTimeline']) { $log = ($run['fullTimeline'].Values -join "`r`n") }
        $isLive = [object]::ReferenceEquals($run, $db['activeRun'])

        $links = @()
        if ($story) {
            $storyHtml = Add-BossIcons (ConvertTo-StoryHtml $story) $run
            $page = "<!doctype html><html><head><meta charset=""utf-8""><title>$([Net.WebUtility]::HtmlEncode($title))</title><style>$pageStyle</style></head><body>" +
                "<h1>$([Net.WebUtility]::HtmlEncode($title))</h1><p class=""meta"">$([Net.WebUtility]::HtmlEncode([string]$run['zone'])) - $([Net.WebUtility]::HtmlEncode([string]$run['startDate']))</p>" +
                "<div class=""story"">$storyHtml</div></body></html>"
            [IO.File]::WriteAllText((Join-Path $outDir "$base.html"), $page, (New-Object Text.UTF8Encoding $false))
            [IO.File]::WriteAllText((Join-Path $outDir "$base.txt"), ((ConvertTo-PlainText $story) -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $false))
            $links += "<a href=""$([Uri]::EscapeDataString("$base.html"))"">story</a>"
        }
        if ($log) {
            [IO.File]::WriteAllText((Join-Path $outDir "$base - Full Log.txt"), ((ConvertTo-PlainText $log) -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $false))
            $links += "<a href=""$([Uri]::EscapeDataString("$base - Full Log.txt"))"">full log</a>"
        }
        $liveTag = if ($isLive) { ' (live run)' } else { '' }
        $noStory = if ($story) { '' } else { ' <span class="meta">no story imported yet</span>' }
        [void]$index.Append("<li>$([Net.WebUtility]::HtmlEncode("$date - $title"))$liveTag : $($links -join ' | ')$noStory</li>")
        $total++
    }
    [void]$index.Append('</ul></body></html>')
    [IO.File]::WriteAllText((Join-Path $outDir 'index.html'), $index.ToString(), (New-Object Text.UTF8Encoding $false))
    Write-Host "  Exported $($runs.Count) adventure(s) to $outDir"
}

if ($total -gt 0 -and -not $env:RPCOPY_NOOPEN) {
    Write-Host ''
    Write-Host "Done. Opening $outRoot"
    Start-Process explorer.exe -ArgumentList "`"$outRoot`""
}
