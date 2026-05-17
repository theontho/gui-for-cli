param(
    [string]$OutputDirectory = "out\release\tauri"
)

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

Invoke-Checked -FilePath npm -Arguments @("--prefix", "platform/typescript", "run", "tauri:dist")

$bundleRoot = Join-Path $PWD "platform\typescript\web\packagers\tauri\target\release\bundle"
$outputRoot = Join-Path $PWD $OutputDirectory
if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$patterns = @(
    "nsis\*.exe"
)
$copied = @()
foreach ($pattern in $patterns) {
    Get-ChildItem -Path (Join-Path $bundleRoot $pattern) -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $outputRoot $_.Name) -Force
        $copied += $_.Name
    }
}

if ($copied.Count -eq 0) {
    throw "No Tauri distribution artifacts were found under $bundleRoot"
}

$manifest = [ordered]@{
    platform = "windows"
    outputDirectory = $OutputDirectory
    artifacts = $copied
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot "tauri-package.json") -Encoding utf8
Write-Output ((Resolve-Path $outputRoot).Path)
