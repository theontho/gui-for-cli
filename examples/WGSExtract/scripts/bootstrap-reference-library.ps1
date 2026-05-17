$ErrorActionPreference = "Stop"

$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
& (Join-Path $bundleRoot "scripts\run-wgsextract.ps1") ref bootstrap --ref $referenceLibrary
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
