# Juju-opplaster
#
# Runs every few minutes (Windows Task Scheduler, see install.ps1):
#  1. Finds Juju.lua in WoW Forever's SavedVariables, reads the line Juju
#     writes on every logout / /reload ( ["upload"] = "JUJU1;..." ) and, if it's
#     newer than the last one sent, POSTs it to the Juju receiver (Cloudflare).
#  2. Downloads the newest community data (SharedData.lua) and puts it in the
#     Juju addon folder, so everyone's drop % is updated after /reload.
#
# Only the upload line (mob ids, kills, item counts) is sent. Nothing else
# from your PC or WoW account. The downloaded file is checked line by line
# against the exact format Juju generates before it is written, since WoW
# runs it as Lua.
param([switch]$Once, [string]$ConfigPath)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $here 'config.json' }
$dataDir = Join-Path $env:LOCALAPPDATA 'JujuUploader'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$logFile = Join-Path $dataDir 'log.txt'
$stateFile = Join-Path $dataDir 'state.json'

function Log([string]$msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    if ((Get-Item $logFile).Length -gt 200KB) {           # keep the log small
        $keep = Get-Content $logFile -Tail 500
        Set-Content -Path $logFile -Value $keep -Encoding UTF8
    }
    Write-Host $line
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $config.endpoint -or $config.endpoint -like '*SETT-INN*') {
    Log 'Ikke konfigurert: config.json mangler adressen til Juju-mottakeren.'
    exit 1
}

# ---------------------------------------------------------------- WoW folder
function Get-ForeverRoots {
    $roots = @()
    if ($config.wowPath) { $roots += $config.wowPath }
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                     'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($p) { $roots += (Split-Path -Parent $p.TrimEnd('\')); $roots += $p }
        } catch {}
    }
    $roots += 'C:\Program Files (x86)\World of Warcraft', 'C:\Program Files\World of Warcraft'
    $found = @()
    foreach ($r in ($roots | Select-Object -Unique)) {
        foreach ($cand in @((Join-Path $r '_forever_'), $r)) {
            if ((Test-Path (Join-Path $cand 'WTF')) -and (Test-Path (Join-Path $cand 'Interface\AddOns'))) {
                $found += (Resolve-Path $cand).Path
            }
        }
    }
    $found | Select-Object -Unique
}

# ---------------------------------------------------------------- state
$state = @{}
if (Test-Path $stateFile) {
    try {
        (Get-Content $stateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
    } catch {}
}
function Save-State { ($state | ConvertTo-Json) | Set-Content -Path $stateFile -Encoding UTF8 }

# ---------------------------------------------------------------- upload
# every "JUJU1;id;serial;..." string Juju wrote: your own record plus what it
# received from other players in-game (["uploads"] list)
$recordRe = '"(JUJU1;([0-9a-fA-F]{4,32});(\d{1,12});[0-9:=,/]*)"'
$batchSize = 50

function Send-Uploads($root) {
    $files = Get-ChildItem -Path (Join-Path $root 'WTF\Account') -Filter 'Juju.lua' -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.DirectoryName -like '*\SavedVariables' }
    # newest record per player id over all accounts/files, not sent before
    $pending = @{}
    foreach ($f in $files) {
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($text, $recordRe)) {
            $id, $serial = $m.Groups[2].Value.ToLower(), [long]$m.Groups[3].Value
            if ($state.ContainsKey($id) -and [long]$state[$id] -ge $serial) { continue }   # already sent
            if ($pending.ContainsKey($id) -and $pending[$id].serial -ge $serial) { continue }
            $pending[$id] = @{ serial = $serial; line = $m.Groups[1].Value }
        }
    }
    if ($pending.Count -eq 0) { return }
    $ids = @($pending.Keys)
    for ($i = 0; $i -lt $ids.Count; $i += $batchSize) {
        $chunk = $ids[$i..([Math]::Min($i + $batchSize, $ids.Count) - 1)]
        $body = ($chunk | ForEach-Object { $pending[$_].line }) -join "`n"
        try {
            $r = Invoke-RestMethod -Uri $config.endpoint -Method Post -Body $body `
                                   -ContentType 'text/plain; charset=utf-8' -TimeoutSec 60
            foreach ($id in $chunk) { $state[$id] = $pending[$id].serial }
            Save-State
            Log ("Sendt: {0} spillere ({1} nye, {2} uendret, {3} avvist), {4} kills" -f `
                 $chunk.Count, $r.saved, $r.upToDate, $r.rejected, $r.kills)
        } catch {
            $code = $null
            try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            if ($code -eq 400) {                       # data the receiver will never accept
                foreach ($id in $chunk) { $state[$id] = $pending[$id].serial }
                Save-State
                Log "Avvist av mottakeren (ugyldige data): $($_.Exception.Message)"
            } else {
                Log "Kunne ikke sende nå (prøver igjen senere): $($_.Exception.Message)"
                return
            }
        }
    }
}

# ---------------------------------------------------------------- download
# every line must look exactly like tools/merge_submissions.py writes it
$okLine = @(
    '^--[^\r\n]*$',
    '^local _, J = \.\.\.$',
    '^J\.SHARED = \{$',
    '^J\.SHARED_CONTRIB = \{$',
    '^\}$',
    '^\[\d{1,8}\]="\d{1,12}\|\d{1,8}\|(\d{1,8}:\d{1,12}(,\d{1,8}:\d{1,12})*)?",$',
    '^\["[0-9a-f]{4,32}"\]=\d{1,12},$'
)

function Test-SharedData([string]$text) {
    if ($text.Length -lt 50 -or $text.Length -gt 20MB) { return $false }
    if (-not $text.Contains('J.SHARED = {') -or -not $text.Contains('J.SHARED_CONTRIB = {')) { return $false }
    foreach ($line in ($text -split "`n")) {
        $l = $line.TrimEnd("`r")
        if ($l -eq '') { continue }
        $ok = $false
        foreach ($re in $okLine) { if ($l -match $re) { $ok = $true; break } }
        if (-not $ok) { return $false }
    }
    return $true
}

function Get-SharedData($root) {
    $addon = Join-Path $root 'Interface\AddOns\Juju'
    if (-not (Test-Path (Join-Path $addon 'Juju.toc'))) { return }
    $item = Get-Item $addon
    if ($item.LinkType) { return }           # developer setup (junction to the repo): git handles it
    try {
        $resp = Invoke-WebRequest -Uri $config.sharedUrl -UseBasicParsing -TimeoutSec 30
        $text = $resp.Content
        if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
    } catch {
        Log "Kunne ikke hente fellesdata nå: $($_.Exception.Message)"
        return
    }
    if (-not (Test-SharedData $text)) { Log 'Fellesdata avvist: uventet innhold (ikke skrevet).'; return }
    $target = Join-Path $addon 'SharedData.lua'
    $old = if (Test-Path $target) { [IO.File]::ReadAllText($target) } else { '' }
    if ($old -ne $text) {
        [IO.File]::WriteAllText($target, $text, (New-Object Text.UTF8Encoding($false)))
        Log 'Fellesdata oppdatert (gjelder etter /reload i spillet).'
    }
}

# ---------------------------------------------------------------- run
$roots = @(Get-ForeverRoots)
if ($roots.Count -eq 0) { Log 'Fant ikke WoW Forever. Sett "wowPath" i config.json.'; exit 1 }
foreach ($root in $roots) {
    try { Send-Uploads $root } catch { Log "Feil ved opplasting: $($_.Exception.Message)" }
    try { Get-SharedData $root } catch { Log "Feil ved henting: $($_.Exception.Message)" }
}
