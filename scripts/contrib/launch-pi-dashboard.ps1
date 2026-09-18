# Starts the PI Dashboard server (detached) and opens it in the browser.
# Safe to run repeatedly: if the server is already up, it just opens the UI.

$ErrorActionPreference = 'Stop'

$port    = 8000
$piPort  = 9999
$url     = "http://localhost:$port"
$cli     = Join-Path $env:APPDATA 'npm\pi-dashboard.cmd'
$logDir  = Join-Path $env:USERPROFILE '.pi\dashboard'
$log     = Join-Path $logDir 'launcher.log'

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    try { Add-Content -LiteralPath $log -Value $line -ErrorAction SilentlyContinue } catch {}
}

if (-not (Test-Path -LiteralPath $cli)) {
    Write-Log "ERROR: pi-dashboard CLI not found at $cli"
    Write-Host "`nPress Enter to close..." -ForegroundColor Yellow
    Read-Host | Out-Null
    exit 1
}

$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue

if ($listening) {
    Write-Log "Dashboard already running (pid $($listening[0].OwningProcess)) on port $port"
}
else {
    Write-Log "Starting PI Dashboard..."
    $proc = Start-Process -FilePath $cli -ArgumentList 'start' `
        -WorkingDirectory $logDir -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(60)
    $up = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            $up = $true
            break
        }
    }

    if ($up) {
        $now = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        Write-Log "Dashboard listening on $url (pid $($now[0].OwningProcess))"
    }
    else {
        Write-Log "WARNING: server did not come up within 60s. See $logDir\server.log"
    }
}

Write-Log "Opening $url"
Start-Process $url

Start-Sleep -Seconds 2
