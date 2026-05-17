$ErrorActionPreference = "Stop"

$repoUrl = if ($env:WGSEXTRACT_REPO_URL) { $env:WGSEXTRACT_REPO_URL } else { "https://github.com/theontho/wgsextract-cli" }
$requestedRef = if ($env:WGSEXTRACT_REF) { $env:WGSEXTRACT_REF } elseif ($env:WGSEXTRACT_RELEASE_TAG) { $env:WGSEXTRACT_RELEASE_TAG } else { "latest" }
$installDir = if ($env:WGSEXTRACT_INSTALL_DIR) { $env:WGSEXTRACT_INSTALL_DIR } else { Join-Path (Get-Location) "runtime\wgsextract-cli" }
$appDir = Join-Path $installDir "app"
$binDir = Join-Path $installDir "bin"
$pixiCacheDir = if ($env:WGSEXTRACT_PIXI_CACHE_DIR) { $env:WGSEXTRACT_PIXI_CACHE_DIR } else { Join-Path $installDir ".pixi\cache" }
$pixiEnvDir = if ($env:WGSEXTRACT_PIXI_ENV_DIR) { $env:WGSEXTRACT_PIXI_ENV_DIR } else { Join-Path $installDir ".pixi\envs" }

function Find-Pixi {
    if ($env:PIXI -and (Test-Path -LiteralPath $env:PIXI -PathType Leaf)) { return $env:PIXI }
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $homePixi -PathType Leaf) { return $homePixi }
    return $null
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8NoBom)
}

function Invoke-PixiInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Pixi,
        [Parameter(Mandatory = $true)][string]$AppDir,
        [Parameter(Mandatory = $true)][string]$PixiEnvDir
    )

    for ($attempt = 1; $attempt -le 2; $attempt += 1) {
        New-Item -ItemType Directory -Force -Path (Join-Path $AppDir ".pixi\envs\default\conda-meta") | Out-Null
        & $Pixi install
        if ($LASTEXITCODE -eq 0) {
            return
        }
        $exitCode = $LASTEXITCODE
        if ($attempt -eq 2) {
            exit $exitCode
        }
        Write-Warning "Pixi install failed with exit code $exitCode. Removing partial default environment and retrying once."
        Remove-Item -LiteralPath (Join-Path $AppDir ".pixi\envs\default") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $PixiEnvDir "default") -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$pixi = Find-Pixi
if (-not $pixi) {
    Write-Host "Installing Pixi..."
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "pixi-install.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://pixi.sh/install.ps1" -OutFile $installer
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
    $pixi = Find-Pixi
    if (-not $pixi) {
        Write-Error "Pixi installation completed, but pixi was not found."
        exit 1
    }
}

if ($env:WGSEXTRACT_ARCHIVE_URL) {
    $archiveUrl = $env:WGSEXTRACT_ARCHIVE_URL
} else {
    if ($requestedRef -eq "latest" -or -not $requestedRef) {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/releases/latest" -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $ref = if ($response.Headers.Location) { Split-Path $response.Headers.Location -Leaf } else { "main" }
    } else {
        $ref = $requestedRef
    }
    $archiveUrl = "$repoUrl/archive/$ref.tar.gz"
}

New-Item -ItemType Directory -Force -Path $installDir, $binDir, (Join-Path $installDir "tmp"), $pixiCacheDir, $pixiEnvDir | Out-Null
$workDir = Join-Path (Join-Path $installDir "tmp") ("install." + [guid]::NewGuid().ToString("N"))
$extractDir = Join-Path $workDir "source"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
$archive = Join-Path $workDir "wgsextract-cli.tar.gz"

try {
    Write-Host "Downloading WGS Extract CLI from $archiveUrl"
    Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $archive
    tar -xzf $archive -C $extractDir
    $sourceDir = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if (-not $sourceDir) {
        Write-Error "Downloaded archive did not contain a source directory."
        exit 1
    }
    $newAppDir = "$appDir.new"
    if (Test-Path -LiteralPath $newAppDir) { Remove-Item -LiteralPath $newAppDir -Recurse -Force }
    Move-Item -LiteralPath $sourceDir.FullName -Destination $newAppDir
    if (Test-Path -LiteralPath $appDir) { Remove-Item -LiteralPath $appDir -Recurse -Force }
    Move-Item -LiteralPath $newAppDir -Destination $appDir

    Write-Host "Installing Pixi environment..."
    New-Item -ItemType Directory -Force -Path (Join-Path $appDir ".pixi\envs\default\conda-meta") | Out-Null
    Push-Location $appDir
    try {
        $env:PIXI_CACHE_DIR = $pixiCacheDir
        $env:PIXI_PROJECT_ENVIRONMENT_DIR = $pixiEnvDir
        Invoke-PixiInstall -Pixi $pixi -AppDir $appDir -PixiEnvDir $pixiEnvDir
        & $pixi run wgsextract --help | Out-Null
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & $pixi run wgsextract deps check
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    $shimPath = Join-Path $binDir "wgsextract.cmd"
    Write-Utf8File -LiteralPath $shimPath -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0..\..\..\scripts\run-wgsextract.ps1"" %*`r`n"
    Write-Host "WGS Extract CLI is installed in $installDir"
} finally {
    if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
}
