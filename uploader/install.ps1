# Installerer Juju-opplasteren for innlogget Windows-bruker (ingen admin nødvendig).
# Kopierer filene til %LOCALAPPDATA%\JujuUploader og lager en planlagt oppgave
# som kjører hvert 5. minutt og ved innlogging, usynlig i bakgrunnen.
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'JujuUploader'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item (Join-Path $src 'JujuUploader.ps1') $dst -Force
if (-not (Test-Path (Join-Path $dst 'config.json'))) {
    Copy-Item (Join-Path $src 'config.json') $dst
} else {
    # keep a wowPath the player set, take the rest from the new version
    $old = Get-Content (Join-Path $dst 'config.json') -Raw | ConvertFrom-Json
    $new = Get-Content (Join-Path $src 'config.json') -Raw | ConvertFrom-Json
    if ($old.wowPath) { $new.wowPath = $old.wowPath }
    ($new | ConvertTo-Json) | Set-Content (Join-Path $dst 'config.json') -Encoding UTF8
}

$script = Join-Path $dst 'JujuUploader.ps1'
$psArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
# conhost --headless (Windows 10 21H2+/11) runs it without a window flashing up
$conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
if ((Test-Path $conhost) -and [Environment]::OSVersion.Version.Build -ge 19044) {
    $action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless powershell.exe $psArgs"
} else {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
}
$every5 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'Juju-opplaster' -Action $action -Trigger @($every5, $logon) `
    -Settings $settings -Principal $principal -Description 'Sender Juju drop-data og henter fellesdata' -Force | Out-Null

Write-Host ''
Write-Host 'Juju-opplasteren er installert.' -ForegroundColor Green
Write-Host "Den kjører hvert 5. minutt. Logg: $dst\log.txt"
Write-Host 'Kjører én gang nå for å teste...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script
