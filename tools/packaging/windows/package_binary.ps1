param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$ZipName
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

Invoke-Checked -FilePath cargo -Arguments @("build", "--manifest-path", $ManifestPath, "--release")

$packageRoot = Join-Path $PWD "$OutputDirectory\package"
$zipPath = Join-Path $PWD "$OutputDirectory\$ZipName"
if (Test-Path $packageRoot) {
    Remove-Item -Recurse -Force $packageRoot
}
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "examples") | Out-Null
Copy-Item $ExecutablePath (Join-Path $packageRoot (Split-Path $ExecutablePath -Leaf))
Copy-Item "examples\WGSExtract" (Join-Path $packageRoot "examples\WGSExtract") -Recurse
Copy-Item "resources" (Join-Path $packageRoot "resources") -Recurse
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath
"Wrote $zipPath"
