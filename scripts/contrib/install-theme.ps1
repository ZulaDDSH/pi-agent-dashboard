# install-theme.ps1 - attach (or detach) the GARDEN pi-dashboard theme.
#
# The theme is a separate stylesheet linked into the dashboard's dist/index.html.
# Upstream CSS is never modified, so re-running this after an
# `npm i -g @blackbelt-technology/pi-agent-dashboard` re-attaches the theme and
# `-Uninstall` fully restores stock appearance.
#
# Usage:
#   .\install-theme.ps1              # attach theme + restart dashboard
#   .\install-theme.ps1 -NoRestart   # attach without restarting
#   .\install-theme.ps1 -Uninstall   # remove the link + restart
#   .\install-theme.ps1 -Status      # report current state

param(
    [switch]$Uninstall,
    [switch]$NoRestart,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$web    = Join-Path $env:APPDATA 'npm\node_modules\@blackbelt-technology\pi-agent-dashboard\node_modules\@blackbelt-technology\pi-dashboard-web\dist'
$html   = Join-Path $web 'index.html'
$theme  = Join-Path $env:USERPROFILE '.pi\dashboard\garden-theme.css'
$marker = '<!-- garden-theme -->'
$linkId = 'garden-theme'
$port   = 8000

function Get-State {
    if (-not (Test-Path -LiteralPath $html)) { return 'no-html' }
    $text = [IO.File]::ReadAllText($html)
    if ($text.Contains($marker)) { return 'installed' }
    return 'stock'
}

function Restart-Dashboard {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($c) {
        Stop-Process -Id $c[0].OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Start-Process -FilePath (Join-Path $env:APPDATA 'npm\pi-dashboard.cmd') `
        -ArgumentList 'start' -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 10
    $up = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($up) { Write-Host "Dashboard restarted on http://localhost:$port" -ForegroundColor Green }
    else     { Write-Host "WARNING: dashboard did not come back up" -ForegroundColor Red }
}

if ($Status) {
    Write-Host ("Theme:   {0}" -f (Get-State))
    Write-Host ("Stylesheet exists: {0}" -f (Test-Path -LiteralPath $theme))
    exit 0
}

if (-not (Test-Path -LiteralPath $theme)) {
    Write-Host "ERROR: theme stylesheet not found: $theme" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $html)) {
    Write-Host "ERROR: dashboard index.html not found: $html" -ForegroundColor Red
    exit 1
}

$state = Get-State

if ($Uninstall) {
    if ($state -eq 'installed') {
        # Restore from backup if we have one, else strip the injected line.
        $bak = "$html.garden-backup"
        if (Test-Path -LiteralPath $bak) {
            Copy-Item -LiteralPath $bak -Destination $html -Force
            Write-Host "Restored index.html from backup." -ForegroundColor Yellow
        } else {
            $text = [IO.File]::ReadAllText($html)
            $text = [regex]::Replace($text, '(?m)^\s*<!-- garden-theme -->.*\r?\n?', '')
            [IO.File]::WriteAllText($html, $text, (New-Object Text.UTF8Encoding($false)))
            Write-Host "Removed theme link." -ForegroundColor Yellow
        }
        if (-not $NoRestart) { Restart-Dashboard }
    } else {
        Write-Host "Theme not installed; nothing to do."
    }
    exit 0
}

if ($state -eq 'installed') {
    Write-Host "Theme already installed. (Re-run after an upgrade; use -Uninstall to remove.)" -ForegroundColor Cyan
    if (-not $NoRestart) { Restart-Dashboard }
    exit 0
}

# Back up once, so -Uninstall can restore byte-identical stock html.
$bak = "$html.garden-backup"
if (-not (Test-Path -LiteralPath $bak)) {
    Copy-Item -LiteralPath $html -Destination $bak -Force
    Write-Host "Backup written: $bak"
}

# Serve the theme from the web root so the browser can fetch it.
$servedTheme = Join-Path $web 'garden-theme.css'
Copy-Item -LiteralPath $theme -Destination $servedTheme -Force

# Cache-bust so a re-install after edits actually reloads.
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tag = "$marker<link rel=`"stylesheet`" id=`"$linkId`" href=`"/garden-theme.css?v=$stamp`">"

$text = [IO.File]::ReadAllText($html)
$text = $text.Replace('</head>', "  $tag`r`n  </head>")
[IO.File]::WriteAllText($html, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host "Theme attached to index.html." -ForegroundColor Green

if (-not $NoRestart) { Restart-Dashboard }
