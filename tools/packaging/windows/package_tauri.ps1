$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "..\..\.."))

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Invoke-Checked -FilePath npm -Arguments @("--prefix", "platform/typescript", "run", "tauri:build", "--", "--bundles", "nsis")

$bundleRoot = Join-Path $PWD "platform\typescript\web\packagers\tauri\target\release\bundle\nsis"
if (-not (Test-Path $bundleRoot)) {
    throw "Tauri NSIS bundle directory was not created: $bundleRoot"
}

$installers = Get-ChildItem -LiteralPath $bundleRoot -Filter "*.exe" -File
if ($installers.Count -eq 0) {
    throw "Tauri NSIS build did not produce an installer in $bundleRoot"
}

$outputRoot = Join-Path $PWD "out\windows-tauri"
if (Test-Path $outputRoot) {
    Remove-Item -Recurse -Force $outputRoot
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

foreach ($installer in $installers) {
    Copy-Item -LiteralPath $installer.FullName -Destination (Join-Path $outputRoot $installer.Name)
}

"Wrote Tauri installer(s) to $outputRoot"
