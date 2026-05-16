param(
    [string]$Node = "",
    [string]$OutputDirectory = "out\windows-webui",
    [string]$BundleRoot = "examples\WGSExtract",
    [int]$Port = 8787
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$resolvedBundleRoot = Resolve-Path (Join-Path $repoRoot $BundleRoot)

function Resolve-RepoChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $combinedPath = if ([System.IO.Path]::IsPathRooted($ChildPath)) {
        $ChildPath
    } else {
        Join-Path $baseFullPath $ChildPath
    }
    $fullPath = [System.IO.Path]::GetFullPath($combinedPath)
    $basePrefix = $baseFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if ($fullPath -eq $baseFullPath -or -not $fullPath.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputDirectory must resolve inside the repository root. Got '$ChildPath'."
    }

    return $fullPath
}

function Resolve-NodeExecutable {
    param([string]$RequestedNode)

    if (-not [string]::IsNullOrWhiteSpace($RequestedNode)) {
        return (Resolve-Path $RequestedNode).Path
    }

    $command = Get-Command node -ErrorAction Stop
    return $command.Source
}

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

$outputRoot = Resolve-RepoChildPath -BasePath $repoRoot -ChildPath $OutputDirectory
$packageRoot = Join-Path $outputRoot "package"
$zipPath = Join-Path $outputRoot "GUIForCLIWebUI-win-x64.zip"
$manifestPath = Join-Path $outputRoot "GUIForCLIWebUI-win-x64-package.json"
$nodePath = Resolve-NodeExecutable $Node

Push-Location $repoRoot
try {
    npm --prefix platform/typescript run build
    if ($LASTEXITCODE -ne 0) {
        throw "WebUI build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $packageRoot | Out-Null

$webuiRoot = Join-Path $packageRoot "platform\typescript"
New-Item -ItemType Directory -Force (Join-Path $webuiRoot "web") | Out-Null
Copy-Directory -Source (Join-Path $repoRoot "platform\typescript\dist") -Destination (Join-Path $webuiRoot "dist")
Copy-Directory -Source (Join-Path $repoRoot "platform\typescript\web\vendor") -Destination (Join-Path $webuiRoot "web\vendor")
Copy-Item -LiteralPath (Join-Path $repoRoot "platform\typescript\web\index.html") -Destination (Join-Path $webuiRoot "web") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "platform\typescript\web\styles.css") -Destination (Join-Path $webuiRoot "web") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "platform\typescript\package.json") -Destination $webuiRoot -Force

$nodeDirectory = Join-Path $packageRoot "node"
New-Item -ItemType Directory -Force $nodeDirectory | Out-Null
Copy-Item -LiteralPath $nodePath -Destination (Join-Path $nodeDirectory "node.exe") -Force

Copy-Directory -Source (Join-Path $repoRoot "resources") `
    -Destination (Join-Path $packageRoot "resources")
Copy-Directory -Source $resolvedBundleRoot.Path `
    -Destination (Join-Path $packageRoot "examples\WGSExtract")

$launcherPath = Join-Path $packageRoot "start-webui.ps1"
$launcher = @"
param(
    [string]`$Bundle = "`$PSScriptRoot\examples\WGSExtract",
    [int]`$Port = $Port,
    [string]`$HostName = "127.0.0.1"
)

`$ErrorActionPreference = "Stop"
`$node = Join-Path `$PSScriptRoot "node\node.exe"
`$server = Join-Path `$PSScriptRoot "platform\typescript\dist\web\src\server\main.js"
& `$node `$server --bundle `$Bundle --port `$Port --host `$HostName
"@
$launcher | Set-Content -LiteralPath $launcherPath -Encoding utf8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

$packageBytes = Get-DirectorySize $packageRoot
$webuiBytes = Get-DirectorySize $webuiRoot
$nodeBytes = (Get-Item -LiteralPath (Join-Path $nodeDirectory "node.exe")).Length
$bundleBytes = Get-DirectorySize (Join-Path $packageRoot "examples\WGSExtract")
$builtinStringsBytes = Get-DirectorySize (Join-Path $packageRoot "resources\BuiltinStrings")
$zipBytes = (Get-Item -LiteralPath $zipPath).Length
$manifest = [ordered]@{
    appName = "GUI for CLI WebUI"
    nodeVersion = (& $nodePath --version)
    nodePath = "node\node.exe"
    defaultPort = $Port
    defaultBundle = "examples\WGSExtract"
    packageDirectory = "package"
    packageZip = "GUIForCLIWebUI-win-x64.zip"
    launcher = "package\start-webui.ps1"
    sizes = [ordered]@{
        packageBytes = $packageBytes
        packageMB = [math]::Round($packageBytes / 1MB, 3)
        packageZipBytes = $zipBytes
        packageZipMB = [math]::Round($zipBytes / 1MB, 3)
        webuiBytes = $webuiBytes
        webuiMB = [math]::Round($webuiBytes / 1MB, 3)
        nodeExeBytes = $nodeBytes
        nodeExeMB = [math]::Round($nodeBytes / 1MB, 3)
        defaultBundleBytes = $bundleBytes
        defaultBundleMB = [math]::Round($bundleBytes / 1MB, 3)
        builtinStringsBytes = $builtinStringsBytes
        builtinStringsMB = [math]::Round($builtinStringsBytes / 1MB, 3)
    }
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    PackageZip = (Resolve-Path $zipPath).Path
    Manifest = (Resolve-Path $manifestPath).Path
    PackageMB = $manifest.sizes.packageMB
    PackageZipMB = $manifest.sizes.packageZipMB
    WebUIMB = $manifest.sizes.webuiMB
    NodeExeMB = $manifest.sizes.nodeExeMB
    DefaultBundleMB = $manifest.sizes.defaultBundleMB
} | ConvertTo-Json
