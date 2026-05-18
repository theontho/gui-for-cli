$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
$runner = Join-Path $scriptDir "run-wgsextract.ps1"
for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    & $runner ref bootstrap --ref $referenceLibrary
    if ($LASTEXITCODE -eq 0) {
        exit 0
    }
    if ($attempt -lt 3) {
        Start-Sleep -Seconds (2 * $attempt)
    }
}
exit $LASTEXITCODE
