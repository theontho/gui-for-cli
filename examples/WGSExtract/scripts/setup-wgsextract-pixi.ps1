$ErrorActionPreference = "Stop"

$repoUrl = if ($env:WGSEXTRACT_REPO_URL) { $env:WGSEXTRACT_REPO_URL } else { "https://github.com/theontho/wgsextract-cli" }
$requestedRef = if ($env:WGSEXTRACT_REF) { $env:WGSEXTRACT_REF } elseif ($env:WGSEXTRACT_RELEASE_TAG) { $env:WGSEXTRACT_RELEASE_TAG } else { "latest" }
$installDir = if ($env:WGSEXTRACT_INSTALL_DIR) { $env:WGSEXTRACT_INSTALL_DIR } else { Join-Path (Get-Location) "runtime\wgsextract-cli" }
$appDir = Join-Path $installDir "app"
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

$pixi = Find-Pixi
if (-not $pixi) {
    Write-Host "Installing Pixi..."
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "pixi-install.ps1"
    Invoke-WebRequest -Uri "https://pixi.sh/install.ps1" -OutFile $installer
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
        $response = Invoke-WebRequest -Uri "$repoUrl/releases/latest" -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $ref = if ($response.Headers.Location) { Split-Path $response.Headers.Location -Leaf } else { "main" }
    } else {
        $ref = $requestedRef
    }
    $archiveUrl = "$repoUrl/archive/$ref.tar.gz"
}

New-Item -ItemType Directory -Force -Path $installDir, (Join-Path $installDir "tmp"), $pixiCacheDir, $pixiEnvDir | Out-Null
$workDir = Join-Path (Join-Path $installDir "tmp") ("install." + [guid]::NewGuid().ToString("N"))
$extractDir = Join-Path $workDir "source"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
$archive = Join-Path $workDir "wgsextract-cli.tar.gz"

try {
    Write-Host "Downloading WGS Extract CLI from $archiveUrl"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archive
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
    Push-Location $appDir
    try {
        $env:PIXI_CACHE_DIR = $pixiCacheDir
        $env:PIXI_PROJECT_ENVIRONMENT_DIR = $pixiEnvDir
        & $pixi install
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & $pixi run wgsextract --help | Out-Null
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & $pixi run wgsextract deps check
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Write-Host "WGS Extract CLI is installed in $installDir"
} finally {
    if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
}
