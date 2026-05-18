$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"
& $runtime wgsextract @args
exit $LASTEXITCODE
