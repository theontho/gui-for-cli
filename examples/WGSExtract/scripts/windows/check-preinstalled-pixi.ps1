$ErrorActionPreference = "Stop"

if ($env:PIXI) {
    if (Test-Path -LiteralPath $env:PIXI -PathType Leaf) {
        Write-Host "Pixi is pre-installed: $env:PIXI"
    } else {
        Write-Host "PIXI is set but is not a file; setup will install Pixi if needed: $env:PIXI"
    }
    exit 0
}

$command = Get-Command pixi -ErrorAction SilentlyContinue
if ($command) {
    Write-Host "Pixi is pre-installed: $($command.Source)"
    exit 0
}

$homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
$runtimePixi = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\wgsextract-cli\.pixi\bin\pixi.exe"
if (Test-Path -LiteralPath $homePixi -PathType Leaf) {
    Write-Host "Pixi is pre-installed: $homePixi"
} elseif (Test-Path -LiteralPath $runtimePixi -PathType Leaf) {
    Write-Host "Pixi is pre-installed: $runtimePixi"
} else {
    Write-Host "Pixi is not pre-installed; setup will install it if needed."
}
