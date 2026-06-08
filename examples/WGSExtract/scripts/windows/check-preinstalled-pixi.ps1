$ErrorActionPreference = "Stop"

function Report-Pixi {
    if ($env:PIXI) {
        if (Test-Path -LiteralPath $env:PIXI -PathType Leaf) {
            Write-Host "Pixi is pre-installed: $env:PIXI"
        } else {
            Write-Host "PIXI is set but is not a file; setup will install Pixi if needed: $env:PIXI"
        }
        return
    }
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command) {
        Write-Host "Pixi is pre-installed: $($command.Source)"
        return
    }
    $homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $homePixi -PathType Leaf) {
        Write-Host "Pixi is pre-installed: $homePixi"
        return
    }
    $runtimePixi = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\wgsextract-cli\.pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $runtimePixi -PathType Leaf) {
        Write-Host "Pixi is pre-installed: $runtimePixi"
    } else {
        Write-Host "Pixi is not pre-installed; setup will install it if needed."
    }
}

function Report-Msys2 {
    $candidates = @()
    if ($env:MSYS2_PATH_TYPE -or $env:MSYSTEM) {
        # Inside an MSYS2 shell; locate root via process bin paths.
    }
    $roots = if ($env:WGSEXTRACT_MSYS2_ROOT) {
        @($env:WGSEXTRACT_MSYS2_ROOT)
    } else {
        @("C:\msys64", "C:\tools\msys64", "C:\msys2", "$env:LOCALAPPDATA\msys64")
    }
    foreach ($root in $roots) {
        if ($root -and (Test-Path -LiteralPath (Join-Path $root "usr\bin\pacman.exe") -PathType Leaf)) {
            $candidates += $root
        }
    }
    $pacmanCmd = Get-Command pacman.exe -ErrorAction SilentlyContinue
    if ($pacmanCmd) {
        $root = (Resolve-Path (Join-Path (Split-Path -Parent $pacmanCmd.Source) "..\..")).Path.TrimEnd('\')
        if ($candidates -notcontains $root) { $candidates += $root }
    }
    if ($candidates.Count -gt 0) {
        Write-Host "MSYS2 is pre-installed: $($candidates[0])"
    } else {
        Write-Host "MSYS2 is not pre-installed; setup will install it if needed."
    }
}

Report-Pixi
Report-Msys2
exit 0
