$ErrorActionPreference = "Stop"

if ($args.Count -lt 1) {
    Write-Error "Usage: run-wgsextract-env.ps1 COMMAND [ARG...]"
    exit 64
}

$scriptDir = Split-Path -Parent $PSCommandPath
$bundleRoot = Split-Path -Parent $scriptDir
$appDir = if ($env:WGSEXTRACT_APP_DIR) { $env:WGSEXTRACT_APP_DIR } else { Join-Path $bundleRoot "runtime\wgsextract-cli\app" }

if (-not (Test-Path -LiteralPath $appDir -PathType Container)) {
    if ($env:WGSEXTRACT_ALLOW_PATH_FALLBACK -eq "1") {
        $candidate = Get-Command $args[0] -ErrorAction SilentlyContinue
        if ($candidate) {
            & $args[0] @($args | Select-Object -Skip 1)
            exit $LASTEXITCODE
        }
    }
    Write-Error "WGS Extract bundle runtime is not installed at $appDir. Run setup before running commands."
    exit 127
}

$pixi = $env:PIXI
if ($pixi -and -not (Test-Path -LiteralPath $pixi -PathType Leaf)) {
    Write-Error "PIXI is set but is not executable: $pixi"
    exit 127
}
if (-not $pixi) {
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command) {
        $pixi = $command.Source
    } else {
        $homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
        if (Test-Path -LiteralPath $homePixi -PathType Leaf) {
            $pixi = $homePixi
        }
    }
}
if (-not $pixi) {
    Write-Error "Pixi was not found. Run setup again or install Pixi first."
    exit 127
}

Push-Location $appDir
try {
    & $pixi run @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
