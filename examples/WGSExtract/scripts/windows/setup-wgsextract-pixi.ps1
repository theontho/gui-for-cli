$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoUrl = if ($env:WGSEXTRACT_REPO_URL) { $env:WGSEXTRACT_REPO_URL } else { "https://github.com/theontho/wgsextract-cli" }
$scriptDir = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $scriptDir
$defaultReleaseTagFile = if ($env:WGSEXTRACT_RELEASE_TAG_FILE) { $env:WGSEXTRACT_RELEASE_TAG_FILE } else { Join-Path $scriptsRoot "wgsextract-release-tag.txt" }
$defaultReleaseTag = if ($env:WGSEXTRACT_DEFAULT_RELEASE_TAG) {
    $env:WGSEXTRACT_DEFAULT_RELEASE_TAG
} elseif (Test-Path -LiteralPath $defaultReleaseTagFile -PathType Leaf) {
    $tag = Get-Content -LiteralPath $defaultReleaseTagFile -TotalCount 1
    if ($tag) { $tag.Trim() } else { "" }
} else {
    ""
}
if (-not $defaultReleaseTag) { $defaultReleaseTag = "latest" }
$requestedRef = if ($env:WGSEXTRACT_REF) { $env:WGSEXTRACT_REF } elseif ($env:WGSEXTRACT_RELEASE_TAG) { $env:WGSEXTRACT_RELEASE_TAG } else { $defaultReleaseTag }
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { Split-Path -Parent $scriptsRoot }
$installDir = if ($env:WGSEXTRACT_INSTALL_DIR) { $env:WGSEXTRACT_INSTALL_DIR } else { Join-Path $bundleRoot "runtime\wgsextract-cli" }
$appDir = Join-Path $installDir "app"
$binDir = Join-Path $installDir "bin"
$pixiEnvDir = if ($env:WGSEXTRACT_PIXI_ENV_DIR) { $env:WGSEXTRACT_PIXI_ENV_DIR } else { Join-Path $appDir ".pixi\envs" }

function Find-Pixi {
    if ($env:PIXI -and (Test-Path -LiteralPath $env:PIXI -PathType Leaf)) { return $env:PIXI }
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $runtimePixi = Join-Path $installDir ".pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $runtimePixi -PathType Leaf) { return $runtimePixi }
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

function Invoke-DownloadWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt += 1) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
            return
        } catch {
            $lastError = $_
            if ($attempt -eq 5) { break }
            Write-Warning "Download failed on attempt $attempt. Retrying in 2 seconds: $Uri"
            Start-Sleep -Seconds 2
        }
    }
    throw $lastError
}

function Get-GitHubCodeloadArchiveUrl {
    param(
        [Parameter(Mandatory = $true)][string]$RepoUrl,
        [Parameter(Mandatory = $true)][string]$Ref
    )

    $cleanRepoUrl = $RepoUrl.TrimEnd("/")
    if ($cleanRepoUrl.EndsWith(".git")) {
        $cleanRepoUrl = $cleanRepoUrl.Substring(0, $cleanRepoUrl.Length - 4)
    }
    $prefix = "https://github.com/"
    if (-not $cleanRepoUrl.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $repoPath = $cleanRepoUrl.Substring($prefix.Length)
    $parts = $repoPath.Split("/")
    if ($parts.Count -lt 2) {
        return $null
    }
    return "https://codeload.github.com/$($parts[0])/$($parts[1])/tar.gz/$Ref"
}

function Get-PixiAssetName {
    $arch = if ($env:PIXI_ARCH) { $env:PIXI_ARCH } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($arch) {
        "^(ARM64|AARCH64)$" { $arch = "aarch64"; break }
        default { $arch = "x86_64" }
    }
    "pixi-$arch-pc-windows-msvc.zip"
}

function Install-PixiWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    $version = if ($env:PIXI_VERSION) { $env:PIXI_VERSION } else { "latest" }
    $repoUrl = if ($env:PIXI_REPOURL) { $env:PIXI_REPOURL.TrimEnd("/") } else { "https://github.com/prefix-dev/pixi" }
    $pixiHome = if ($env:PIXI_HOME) { $env:PIXI_HOME } else { Join-Path $installDir ".pixi" }
    $pixiBinDir = if ($env:PIXI_BIN_DIR) { $env:PIXI_BIN_DIR } else { Join-Path $pixiHome "bin" }
    $assetName = Get-PixiAssetName
    $downloadUrl = if ($env:PIXI_DOWNLOAD_URL) {
        $env:PIXI_DOWNLOAD_URL
    } elseif ($version -eq "latest") {
        "$repoUrl/releases/latest/download/$assetName"
    } else {
        "$repoUrl/releases/download/v$($version.TrimStart("v"))/$assetName"
    }

    Write-Host "Downloading Pixi from $downloadUrl"
    New-Item -ItemType Directory -Force -Path $pixiBinDir | Out-Null
    $archive = Join-Path $WorkDir $assetName
    $extractDir = Join-Path $WorkDir "pixi"
    Invoke-DownloadWithRetry -Uri $downloadUrl -OutFile $archive
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
    $pixiBinary = Get-ChildItem -LiteralPath $extractDir -Filter "pixi.exe" -Recurse -File | Select-Object -First 1
    if (-not $pixiBinary) {
        Write-Error "Downloaded Pixi archive did not contain pixi.exe."
        exit 1
    }
    Copy-Item -LiteralPath $pixiBinary.FullName -Destination (Join-Path $pixiBinDir "pixi.exe") -Force
    return Join-Path $pixiBinDir "pixi.exe"
}

function Invoke-PixiInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Pixi,
        [Parameter(Mandatory = $true)][string]$AppDir,
        [Parameter(Mandatory = $true)][string]$PixiEnvDir,
        [Parameter(Mandatory = $true)][string]$Archive
    )

    for ($attempt = 1; $attempt -le 2; $attempt += 1) {
        Restore-AppSource -Archive $Archive -AppDir $AppDir
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

function Restore-AppSource {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$AppDir
    )

    if (Test-Path -LiteralPath (Join-Path $AppDir "pyproject.toml") -PathType Leaf) {
        return
    }

    $newAppDir = "$AppDir.new"
    if (Test-Path -LiteralPath $newAppDir) { Remove-Item -LiteralPath $newAppDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $newAppDir | Out-Null
    tar -xzf $Archive -C $newAppDir --strip-components=1
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    if (-not (Test-Path -LiteralPath (Join-Path $newAppDir "pyproject.toml") -PathType Leaf)) {
        Write-Error "Downloaded archive did not contain pyproject.toml."
        exit 1
    }
    if (Test-Path -LiteralPath $AppDir) { Remove-Item -LiteralPath $AppDir -Recurse -Force }
    Move-Item -LiteralPath $newAppDir -Destination $AppDir
}

$pixi = Find-Pixi
$pixiInstalledBySetup = $false
if (-not $pixi) {
    Write-Host "Installing Pixi..."
    $pixiInstallWorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pixi-install." + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $pixiInstallWorkDir | Out-Null
    try {
        $pixi = Install-PixiWithRetry -WorkDir $pixiInstallWorkDir
    } finally {
        if (Test-Path -LiteralPath $pixiInstallWorkDir) { Remove-Item -LiteralPath $pixiInstallWorkDir -Recurse -Force }
    }
    $pixiInstalledBySetup = $true
    if (-not $pixi) {
        Write-Error "Pixi installation completed, but pixi was not found."
        exit 1
    }
}

$archiveFallbackUrl = $null
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
    $archiveFallbackUrl = Get-GitHubCodeloadArchiveUrl -RepoUrl $repoUrl -Ref $ref
}

New-Item -ItemType Directory -Force -Path $installDir, (Join-Path $installDir "tmp"), $binDir, $pixiEnvDir | Out-Null
$workDir = Join-Path (Join-Path $installDir "tmp") ("install." + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$archive = Join-Path $workDir "wgsextract-cli.tar.gz"

try {
    Write-Host "Downloading WGS Extract CLI from $archiveUrl"
    try {
        Invoke-DownloadWithRetry -Uri $archiveUrl -OutFile $archive
    } catch {
        if (-not $archiveFallbackUrl -or $archiveFallbackUrl -eq $archiveUrl) {
            throw
        }
        Write-Warning "Primary source archive download failed. Downloading from $archiveFallbackUrl"
        if (Test-Path -LiteralPath $archive -PathType Leaf) { Remove-Item -LiteralPath $archive -Force }
        Invoke-DownloadWithRetry -Uri $archiveFallbackUrl -OutFile $archive
    }
    Restore-AppSource -Archive $archive -AppDir $appDir

    Write-Host "Installing Pixi environment..."
    New-Item -ItemType Directory -Force -Path (Join-Path $appDir ".pixi\envs\default\conda-meta") | Out-Null
    Push-Location $appDir
    try {
        if ($env:WGSEXTRACT_PIXI_CACHE_DIR) {
            New-Item -ItemType Directory -Force -Path $env:WGSEXTRACT_PIXI_CACHE_DIR | Out-Null
            $env:PIXI_CACHE_DIR = $env:WGSEXTRACT_PIXI_CACHE_DIR
        } elseif ($pixiInstalledBySetup) {
            $localPixiCacheDir = Join-Path $installDir ".pixi\cache"
            New-Item -ItemType Directory -Force -Path $localPixiCacheDir | Out-Null
            $env:PIXI_CACHE_DIR = $localPixiCacheDir
        }
        $env:PIXI_PROJECT_ENVIRONMENT_DIR = $pixiEnvDir
        Invoke-PixiInstall -Pixi $pixi -AppDir $appDir -PixiEnvDir $pixiEnvDir -Archive $archive
        & $pixi run wgsextract --help | Out-Null
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & $pixi run wgsextract deps check
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    $shimPath = Join-Path $binDir "wgsextract.cmd"
    $runScript = Join-Path $scriptDir "run-wgsextract.ps1"
    Write-Utf8File -LiteralPath $shimPath -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$runScript"" %*`r`n"
    Write-Host "WGS Extract CLI is installed in $installDir"
} finally {
    if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
}
