# Fjerner Juju-opplasteren (planlagt oppgave + filer).
$ErrorActionPreference = 'SilentlyContinue'
Unregister-ScheduledTask -TaskName 'Juju-opplaster' -Confirm:$false
Remove-Item (Join-Path $env:LOCALAPPDATA 'JujuUploader') -Recurse -Force -Confirm:$false
Write-Host 'Juju-opplasteren er fjernet.' -ForegroundColor Green
