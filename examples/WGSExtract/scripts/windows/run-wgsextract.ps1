$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$commandArgs = @($args)
if ($commandArgs.Count -gt 0 -and $commandArgs[0] -eq "microarray") {
    & (Join-Path $scriptDir "run-wgsextract-microarray.ps1") @commandArgs
    exit $LASTEXITCODE
}

$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"
if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
    $input | & $runtime wgsextract @args
} else {
    & $runtime wgsextract @args
}
exit $LASTEXITCODE
