param(
    [string]$OutputDirectory = "out\windows-gio",
    [string]$BundleRoot = "examples\WGSExtract"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputRoot = Join-Path $repoRoot $OutputDirectory
$packageRoot = Join-Path $outputRoot "package"
$zipPath = Join-Path $outputRoot "GUIForCLIGio-win-x64.zip"
$manifestPath = Join-Path $outputRoot "GUIForCLIGio-win-x64-package.json"
$resolvedBundleRoot = Resolve-Path (Join-Path $repoRoot $BundleRoot)
$resourcesRoot = Join-Path $repoRoot "resources"
$appRoot = Join-Path $repoRoot "exp-platform\go\gio"

function Copy-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force (Split-Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Get-DirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return 0
    }

    return (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object Length -Sum).Sum
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $packageRoot | Out-Null

Push-Location $appRoot
try {
    go mod tidy
    if ($LASTEXITCODE -ne 0) {
        throw "go mod tidy failed with exit code $LASTEXITCODE."
    }

    go build -trimpath -ldflags "-s -w" -o (Join-Path $packageRoot "gui-for-cli-gio.exe") .
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

Copy-Directory -Source $resolvedBundleRoot.Path -Destination (Join-Path $packageRoot "examples\WGSExtract")
Copy-Directory -Source $resourcesRoot -Destination (Join-Path $packageRoot "resources")

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

$exePath = Join-Path $packageRoot "gui-for-cli-gio.exe"
$packageBytes = Get-DirectorySize $packageRoot
$bundleBytes = Get-DirectorySize (Join-Path $packageRoot "examples\WGSExtract")
$builtinsBytes = Get-DirectorySize (Join-Path $packageRoot "resources\BuiltinStrings")
$zipBytes = (Get-Item -LiteralPath $zipPath).Length
$exeBytes = (Get-Item -LiteralPath $exePath).Length

$manifest = [ordered]@{
    appName = "GUI for CLI Gio"
    packageDirectory = "package"
    packageZip = "GUIForCLIGio-win-x64.zip"
    executable = "package\gui-for-cli-gio.exe"
    defaultBundle = "examples\WGSExtract"
    builtinStrings = "resources\BuiltinStrings"
    sizes = [ordered]@{
        packageBytes = $packageBytes
        packageMB = [math]::Round($packageBytes / 1MB, 3)
        packageZipBytes = $zipBytes
        packageZipMB = [math]::Round($zipBytes / 1MB, 3)
        executableBytes = $exeBytes
        executableMB = [math]::Round($exeBytes / 1MB, 3)
        defaultBundleBytes = $bundleBytes
        defaultBundleMB = [math]::Round($bundleBytes / 1MB, 3)
        builtinStringsBytes = $builtinsBytes
        builtinStringsMB = [math]::Round($builtinsBytes / 1MB, 3)
    }
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    PackageZip = (Resolve-Path $zipPath).Path
    Manifest = (Resolve-Path $manifestPath).Path
    PackageMB = $manifest.sizes.packageMB
    PackageZipMB = $manifest.sizes.packageZipMB
    ExecutableMB = $manifest.sizes.executableMB
} | ConvertTo-Json
