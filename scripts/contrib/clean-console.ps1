# clean-console.ps1 - strip browser-console stack traces from text on the clipboard.
#
# A pasted Chrome/Edge console dump is ~90% repeated React/Vite stack frames.
# This keeps the lines that carry information (the error lines, messages, and
# the first few frames) and drops the rest, then puts the result back on the
# clipboard so it can be pasted straight into an agent.
#
# Usage:
#   .\clean-console.ps1                 # read + clean + write back to clipboard
#   .\clean-console.ps1 -Show           # also print the result
#   .\clean-console.ps1 -File in.txt    # read a file instead of the clipboard
#   .\clean-console.ps1 -OutFile o.txt  # write to a file instead of the clipboard

param(
    [switch]$Show,
    [string]$File,
    [string]$OutFile,
    [int]$MaxFramesPerError = 3
)

$ErrorActionPreference = 'Stop'

function Get-InputText {
    if ($File) { return [IO.File]::ReadAllText($File) }
    Add-Type -AssemblyName System.Windows.Forms
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        return [System.Windows.Forms.Clipboard]::GetText()
    }
    return ''
}

# Stack-frame lines emitted by the browser. These are the bulk of the noise.
$framePatterns = @(
    '^\s*at\s',                        # "  at fn (file:line)"
    '^\s*\w+\s*@\s*\S+\.js',           # "fn @ file.js:48"
    '^\s*\(anonymous\)\s*@',           # "(anonymous) @ file.js:48"
    '\breact-vendor[-.\w]*\.js',
    '\bvendor-[\w-]+\.js',
    '\bindex-[\w-]+\.js:\d+',
    '^\s*postMessage\s*$',
    '^\s*setInterval\s*$',
    '^\s*Promise\.catch\s*$'
)
$frameRegex = ($framePatterns -join '|')

# Documented "first N frames" budget, counted per contiguous frame block.
$result = New-Object System.Collections.Generic.List[string]
$framesInBlock = 0
$lastWasKept = $false

foreach ($line in (Get-InputText) -split "`r?`n") {
    $isFrame = $line -match $frameRegex

    if (-not $isFrame) {
        $framesInBlock  = 0
        $lastWasKept    = $false
        $result.Add($line)
        continue
    }

    if ($framesInBlock -lt $MaxFramesPerError) {
        $framesInBlock++
        $result.Add($line)
        $lastWasKept = $true
    }
    else {
        if ($lastWasKept) { $result.Add('    [... stack frames omitted ...]') }
        $lastWasKept = $false
    }
}

$out = ($result -join "`r`n").TrimEnd()
# Collapse the runs of blank lines that dropping frames leaves behind.
$out = [regex]::Replace($out, "(\r?\n){3,}", "`r`n`r`n")

if ($OutFile) {
    [IO.File]::WriteAllText($OutFile, $out, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Wrote $OutFile"
}
elseif ($File) {
    if ($Show) { Write-Host $out }
}
else {
    [System.Windows.Forms.Clipboard]::SetText($out)
    Write-Host "Cleaned clipboard."
}

if ($Show -or $OutFile) {
    $inLen  = (Get-InputText).Length
    $pct    = if ($inLen -gt 0) { [math]::Round(100 - ($out.Length / $inLen * 100), 1) } else { 0 }
    Write-Host ("  {0} -> {1} chars  ({2}% smaller)" -f $inLen, $out.Length, $pct)
}
