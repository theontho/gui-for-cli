param(
    [string]$DotNet = "dotnet",
    [string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$OutputDirectory = "out\windows-bootstrap",
    [switch]$IncludeSymbols
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$project = Join-Path $repoRoot "exp-platform\windows\dotnet\GUIForCLIWindows\GUIForCLIWindows.csproj"
$platform = switch ($RuntimeIdentifier) {
    "win-x86" { "x86" }
    "win-x64" { "x64" }
    "win-arm64" { "ARM64" }
    default { throw "Unsupported RuntimeIdentifier '$RuntimeIdentifier'. Expected win-x86, win-x64, or win-arm64." }
}

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

function Get-DirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return 0
    }

    return (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object Length -Sum).Sum
}

function Copy-RelativeFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $relativePath = $File.FullName.Substring($SourceRoot.Length + 1)
    $destination = Join-Path $DestinationRoot $relativePath
    $destinationParent = Split-Path $destination -Parent
    New-Item -ItemType Directory -Force $destinationParent | Out-Null
    Copy-Item -LiteralPath $File.FullName -Destination $destination -Force
}

$outputRoot = Resolve-RepoChildPath -BasePath $repoRoot -ChildPath $OutputDirectory
$publishDirectory = Join-Path $outputRoot "framework-dependent"
$payloadDirectory = Join-Path $outputRoot "payload"
$zipPath = Join-Path $outputRoot "GUIForCLIWindows-$RuntimeIdentifier-app.zip"
$manifestPath = Join-Path $outputRoot "GUIForCLIWindows-$RuntimeIdentifier-bootstrap.json"

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $publishDirectory, $payloadDirectory | Out-Null

& $DotNet publish $project `
    -c $Configuration `
    -o $publishDirectory `
    -p:Platform=$platform `
    -p:RuntimeIdentifier=$RuntimeIdentifier `
    -p:SelfContained=false `
    -p:WindowsAppSDKSelfContained=false `
    /nr:false
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$publishRoot = (Resolve-Path $publishDirectory).Path
$publishFiles = Get-ChildItem -LiteralPath $publishRoot -Recurse -File
$payloadFiles = $publishFiles | Where-Object {
    $relativePath = $_.FullName.Substring($publishRoot.Length + 1)
    $isAppFile = $_.Name -like "GUIForCLIWindows*" `
        -or $_.Name -like "GUIForCLIWindows.Core*" `
        -or $_.Extension -eq ".pri" `
        -or $relativePath -like "Assets\*" `
        -or $relativePath -like "Resources\*" `
        -or $_.Name -eq "AppxManifest.xml"
    $isAppFile -and ($IncludeSymbols -or $_.Extension -ne ".pdb")
}

foreach ($file in $payloadFiles) {
    Copy-RelativeFile -File $file -SourceRoot $publishRoot -DestinationRoot $payloadDirectory
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $payloadDirectory "*") -DestinationPath $zipPath -CompressionLevel Optimal

$payloadBytes = Get-DirectorySize $payloadDirectory
$publishBytes = Get-DirectorySize $publishDirectory
$zipBytes = (Get-Item -LiteralPath $zipPath).Length
$frameworkBytes = $publishBytes - $payloadBytes
$manifest = [ordered]@{
    appName = "GUI for CLI"
    runtimeIdentifier = $RuntimeIdentifier
    configuration = $Configuration
    targetFramework = "net10.0-windows10.0.19041.0"
    selfContained = $false
    windowsAppSDKSelfContained = $false
    includesSymbols = [bool]$IncludeSymbols
    payloadZip = "GUIForCLIWindows-$RuntimeIdentifier-app.zip"
    payloadDirectory = "payload"
    frameworkDependentPublishDirectory = "framework-dependent"
    installPrerequisites = @(
        ".NET Desktop Runtime compatible with net10.0-windows10.0.19041.0 for $platform"
        "Windows App SDK runtime compatible with the app package references for $platform"
    )
    sizes = [ordered]@{
        appPayloadBytes = $payloadBytes
        appPayloadMB = [math]::Round($payloadBytes / 1MB, 3)
        appPayloadZipBytes = $zipBytes
        appPayloadZipMB = [math]::Round($zipBytes / 1MB, 3)
        frameworkDependentPublishBytes = $publishBytes
        frameworkDependentPublishMB = [math]::Round($publishBytes / 1MB, 3)
        frameworkAndRuntimePayloadBytes = $frameworkBytes
        frameworkAndRuntimePayloadMB = [math]::Round($frameworkBytes / 1MB, 3)
    }
    payloadFiles = @($payloadFiles | ForEach-Object { $_.FullName.Substring($publishRoot.Length + 1) } | Sort-Object)
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

[pscustomobject]@{
    PayloadZip = (Resolve-Path $zipPath).Path
    Manifest = (Resolve-Path $manifestPath).Path
    AppPayloadMB = $manifest.sizes.appPayloadMB
    AppPayloadZipMB = $manifest.sizes.appPayloadZipMB
    FrameworkDependentPublishMB = $manifest.sizes.frameworkDependentPublishMB
    FrameworkAndRuntimePayloadMB = $manifest.sizes.frameworkAndRuntimePayloadMB
} | ConvertTo-Json
