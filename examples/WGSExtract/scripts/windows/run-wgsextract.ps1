$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"
if ($MyInvocation.ExpectingInput) {
    $input | & $runtime wgsextract @args
} else {
    & $runtime wgsextract @args
}
exit $LASTEXITCODE
