$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }
$bootstrapArgs = @("ref", "bootstrap", "--ref", $referenceLibrary)

if ($env:WGSEXTRACT_SKIP_MAPPABILITY_MAPS -ne "1") {
    $bootstrapArgs += "--install-mappability-maps"
}

& (Join-Path $scriptDir "run-wgsextract.ps1") @bootstrapArgs
exit $LASTEXITCODE
