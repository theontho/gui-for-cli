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

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8NoBom)
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
Write-Utf8File -LiteralPath (Join-Path $outputRoot "tauri-package.json") -Value (($manifest | ConvertTo-Json -Depth 4) + "`n")
Write-Output ((Resolve-Path $outputRoot).Path)
