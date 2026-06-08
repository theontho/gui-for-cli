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

$msys2Root = if ($env:WGSEXTRACT_MSYS2_ROOT) {
    $env:WGSEXTRACT_MSYS2_ROOT
} elseif ($env:MSYS2_ROOT) {
    $env:MSYS2_ROOT
} else {
    "C:\msys64"
}

function Test-MsysInstall {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root "usr\bin\pacman.exe") -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Root "usr\bin\bash.exe") -PathType Leaf)
}

function Find-Pixi {
    if ($env:PIXI -and (Test-Path -LiteralPath $env:PIXI -PathType Leaf)) { return $env:PIXI }
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command -and $command.Path) { return $command.Path }
    if ($command -and $command.Source) { return $command.Source }
    $runtimePixi = Join-Path $installDir ".pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $runtimePixi -PathType Leaf) { return $runtimePixi }
    $homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
    if (Test-Path -LiteralPath $homePixi -PathType Leaf) { return $homePixi }
    return $null
}

function Install-PixiFromApi {
    # Bypass the flaky github.com edge for release downloads by going through
    # api.github.com. When github.com/.../releases/.../<asset>.zip 504s, the
    # API endpoint with `Accept: application/octet-stream` still serves the
    # asset (likely a different CDN path).
    $existing = Find-Pixi
    if ($existing) { return $existing }
    Write-Host "Pre-installing Pixi via api.github.com (bypasses github.com edge 504s)..."

    $assetName = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'pixi-aarch64-pc-windows-msvc.zip' } else { 'pixi-x86_64-pc-windows-msvc.zip' }
    $zipPath = Get-GitHubReleaseAsset -Owner 'prefix-dev' -Repo 'pixi' -Tag 'latest' -AssetName $assetName -Label 'Pixi'

    $pixiBinDir = Join-Path $HOME ".pixi\bin"
    New-Item -ItemType Directory -Force -Path $pixiBinDir | Out-Null

    # Extract to a staging directory so a parallel/orphan process that's also
    # placing pixi.exe at the destination can't make Expand-Archive blow up
    # mid-stream. Then move into place with retry. If the destination is
    # already populated by the time we get here, leave it alone.
    $stageDir = Join-Path $env:TEMP ("pixi-stage-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $stageDir -Force
        Remove-Item -LiteralPath (Split-Path -Parent $zipPath) -Recurse -Force -ErrorAction SilentlyContinue

        $stagedPixi = Join-Path $stageDir "pixi.exe"
        if (-not (Test-Path -LiteralPath $stagedPixi -PathType Leaf)) {
            throw "Pixi zip did not contain pixi.exe (looked in $stageDir)"
        }

        $destPixi = Join-Path $pixiBinDir "pixi.exe"
        $moveAttempts = 6
        for ($i = 1; $i -le $moveAttempts; $i += 1) {
            if (Test-Path -LiteralPath $destPixi -PathType Leaf) { break }
            try {
                Move-Item -LiteralPath $stagedPixi -Destination $destPixi -ErrorAction Stop
                break
            }
            catch {
                if ($i -eq $moveAttempts) { throw }
                Start-Sleep -Milliseconds (500 * $i)
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $pixiExe = Join-Path $pixiBinDir "pixi.exe"
    if (-not (Test-Path -LiteralPath $pixiExe -PathType Leaf)) {
        throw "pixi.exe is still missing at $pixiExe after install attempt"
    }

    # Make sure the bin dir is on User PATH so subsequent steps (and the
    # upstream installer's idempotent check) find it.
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $entries = @(); if ($userPath) { $entries = $userPath -split ';' }
    if (-not ($entries | Where-Object { $_.TrimEnd('\') -eq $pixiBinDir.TrimEnd('\') })) {
        $entries += $pixiBinDir
        [Environment]::SetEnvironmentVariable("PATH", ($entries -join ';'), "User")
    }
    $env:PATH = "$pixiBinDir;$env:PATH"
    $env:PIXI = $pixiExe
    Write-Host "Pixi installed at $pixiExe"
    return $pixiExe
}

function Get-GitHubReleaseAsset {
    # Generic helper: download a release asset via api.github.com to a temp
    # file and return its local path. Used to bypass github.com edge 504s.
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,    # 'latest' or 'tags/<tag>'
        [Parameter(Mandatory = $true)][string]$AssetName,
        [string]$Label = "asset"
    )

    if ($Tag -eq 'latest') {
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    } else {
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
    }
    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'wgsextract-installer' }
    $release = $null
    for ($i = 1; $i -le 5; $i += 1) {
        try { $release = Invoke-RestMethod -UseBasicParsing -Uri $apiUrl -Headers $headers -TimeoutSec 60; break }
        catch {
            if ($i -eq 5) { throw "Failed to query $apiUrl after 5 attempts: $($_.Exception.Message)" }
            Start-Sleep -Seconds (5 * $i)
        }
    }
    $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $asset) { throw "$Label release $($release.tag_name) does not include asset $AssetName" }

    $downloadDir = Join-Path $env:TEMP ("gh-asset-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $assetPath = Join-Path $downloadDir $AssetName
    $assetHeaders = @{ 'Accept' = 'application/octet-stream'; 'User-Agent' = 'wgsextract-installer' }
    for ($i = 1; $i -le 5; $i += 1) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $asset.url -Headers $assetHeaders -OutFile $assetPath -TimeoutSec 600; break }
        catch {
            if ($i -eq 5) { throw "Failed to download $Label asset after 5 attempts: $($_.Exception.Message)" }
            Start-Sleep -Seconds (5 * $i)
        }
    }
    Write-Host "Downloaded $Label asset $AssetName from release $($release.tag_name) ($(($asset.size / 1MB).ToString('N1')) MB)"
    return $assetPath
}

function Install-Msys2SfxFromApi {
    # Pre-download MSYS2 SFX via api.github.com so the upstream bootstrap
    # script can install MSYS2 from a local file (Copy-UrlOrFile checks
    # Test-Path on the source first). This bypasses the github.com edge that
    # intermittently returns 504 for release downloads.
    param([string]$Msys2Root)

    if (Test-Path -LiteralPath (Join-Path $Msys2Root "usr\bin\bash.exe") -PathType Leaf) {
        return $null
    }
    Write-Host "Pre-downloading MSYS2 SFX via api.github.com (bypasses github.com edge 504s)..."
    return Get-GitHubReleaseAsset -Owner 'msys2' -Repo 'msys2-installer' -Tag 'latest' `
        -AssetName 'msys2-base-x86_64-latest.sfx.exe' -Label 'MSYS2'
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8NoBom)
}

function Remove-DirectoryWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Attempts = 8
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($i = 1; $i -le $Attempts; $i += 1) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Start-Sleep -Milliseconds (500 * $i)
        }
    }
}

function Restore-AppSource {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$AppDir
    )

    # A complete extract has both install_windows.bat and pixi.toml at the
    # root. If only install_windows.bat is present, a previous run was
    # interrupted mid-extract — re-extract instead of trusting the partial
    # state. We also clean up any stale .new sibling and any leftover
    # app.new subdirectory left under a previous partial extract.
    $alreadyExtracted = (Test-Path -LiteralPath (Join-Path $AppDir "install_windows.bat") -PathType Leaf) -and
                        (Test-Path -LiteralPath (Join-Path $AppDir "pixi.toml") -PathType Leaf)
    if ($alreadyExtracted) {
        $staleNew = Join-Path $AppDir "app.new"
        Remove-DirectoryWithRetry -Path $staleNew
        return
    }

    $newAppDir = "$AppDir.new"
    Remove-DirectoryWithRetry -Path $newAppDir
    New-Item -ItemType Directory -Force -Path $newAppDir | Out-Null
    tar -xzf $Archive -C $newAppDir --strip-components=1
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not (Test-Path -LiteralPath (Join-Path $newAppDir "install_windows.bat") -PathType Leaf)) {
        Write-Error "Downloaded archive did not contain install_windows.bat."
        exit 1
    }
    if (-not (Test-Path -LiteralPath (Join-Path $newAppDir "pixi.toml") -PathType Leaf)) {
        Write-Error "Downloaded archive did not contain pixi.toml."
        exit 1
    }
    if (Test-Path -LiteralPath $AppDir) { Remove-DirectoryWithRetry -Path $AppDir }

    # Antivirus (Defender) and tar.exe sometimes briefly hold files inside the
    # freshly-extracted directory. Retry Move-Item a few times before giving up.
    $attempts = 6
    for ($i = 1; $i -le $attempts; $i += 1) {
        try {
            Move-Item -LiteralPath $newAppDir -Destination $AppDir -ErrorAction Stop
            return
        }
        catch {
            if ($i -eq $attempts) { throw }
            Start-Sleep -Milliseconds (500 * $i)
        }
    }
}

# Pre-state snapshot so the manifest records who owns each prerequisite.
$msys2PreInstalled = Test-MsysInstall -Root $msys2Root
$pixiPreInstalled = ($null -ne (Find-Pixi))

if ($env:WGSEXTRACT_ARCHIVE_URL) {
    $archiveUrls = @($env:WGSEXTRACT_ARCHIVE_URL)
} else {
    if ($requestedRef -eq "latest" -or -not $requestedRef) {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/releases/latest" -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $ref = if ($response.Headers.Location) { Split-Path $response.Headers.Location -Leaf } else { "main" }
    } else {
        $ref = $requestedRef
    }
    # Build a fallback list. github.com/.../archive/$ref.tar.gz is the
    # canonical URL but it intermittently returns 504 from the github.com
    # edge while the underlying codeload CDN remains healthy. Always include
    # codeload as a fallback so flaky edge outages don't break setup.
    $archiveUrls = @("$repoUrl/archive/$ref.tar.gz")
    if ($repoUrl -match '^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$') {
        $owner = $Matches[1]
        $repo = $Matches[2]
        if ($ref -like 'v*' -or $ref -match '^\d') {
            $archiveUrls += "https://codeload.github.com/$owner/$repo/tar.gz/refs/tags/$ref"
        }
        $archiveUrls += "https://codeload.github.com/$owner/$repo/tar.gz/refs/heads/$ref"
        $archiveUrls += "https://codeload.github.com/$owner/$repo/tar.gz/$ref"
    }
}

New-Item -ItemType Directory -Force -Path $installDir, (Join-Path $installDir "tmp"), $binDir | Out-Null
$workDir = Join-Path (Join-Path $installDir "tmp") ("install." + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$archive = Join-Path $workDir "wgsextract-cli.tar.gz"

try {
    $downloadAttempts = 5
    $downloaded = $false
    foreach ($currentUrl in $archiveUrls) {
        Write-Host "Downloading WGS Extract CLI from $currentUrl"
        for ($attempt = 1; $attempt -le $downloadAttempts; $attempt += 1) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $currentUrl -OutFile $archive -TimeoutSec 120
                $downloaded = $true
                break
            }
            catch {
                $message = $_.Exception.Message
                if ($attempt -eq $downloadAttempts) {
                    Write-Host "All $downloadAttempts attempts failed for $currentUrl ($message). Trying next fallback URL if any..."
                    break
                }
                $delay = [int][math]::Min(60, [math]::Pow(2, $attempt))
                Write-Host "Download attempt $attempt/$downloadAttempts failed ($message). Retrying in $delay s..."
                Start-Sleep -Seconds $delay
            }
        }
        if ($downloaded) { break }
    }
    if (-not $downloaded) {
        throw "Failed to download WGS Extract CLI from any of: $($archiveUrls -join ', ')"
    }
    Restore-AppSource -Archive $archive -AppDir $appDir

    $installBat = Join-Path $appDir "install_windows.bat"
    if (-not (Test-Path -LiteralPath $installBat -PathType Leaf)) {
        Write-Error "Upstream install_windows.bat not found at $installBat. Tarball layout changed?"
        exit 1
    }

    # Defensive patch for wgsextract-cli <= v0.3.5 bug: bootstrap_windows_prereqs.ps1
    # builds `-o"C:\"` for the MSYS2 SFX extractor, where the trailing `\"` is
    # mis-parsed by Start-Process and 7-Zip exits with code 2. Rewrite in place.
    # Remove once we depend on a release that contains the upstream fix.
    $bootstrapPath = Join-Path $appDir "scripts\bootstrap_windows_prereqs.ps1"
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
        $bootstrapContent = Get-Content -LiteralPath $bootstrapPath -Raw
        $buggyPattern = "`$outputArg = '-o`"{0}`"' -f `$extractParent"
        if ($bootstrapContent.Contains($buggyPattern)) {
            $patched = @"
`$normalizedParent = `$extractParent.TrimEnd([char[]]@('\','/'))
            if ([string]::IsNullOrEmpty(`$normalizedParent)) { `$normalizedParent = `$extractParent }
            if (`$normalizedParent -match '\s') { `$outputArg = "-o```"`$normalizedParent```"" } else { `$outputArg = "-o`$normalizedParent" }
"@
            $bootstrapContent = $bootstrapContent.Replace($buggyPattern, $patched)
            Write-Utf8File -LiteralPath $bootstrapPath -Value $bootstrapContent
            Write-Host "Patched upstream bootstrap_windows_prereqs.ps1 for MSYS2 SFX -o argument quoting bug."
        }
    }

    # Defensive patch for wgsextract-cli <= v0.3.5: install_windows.bat unconditionally
    # overrides PIXI_CACHE_DIR / PIXI_PROJECT_ENVIRONMENT_DIR to paths under the bundle
    # workspace, which on Windows often exceeds MAX_PATH (260) during pixi install.
    # Make those assignments respect pre-existing env vars so we can redirect them
    # outside the workspace. Remove once upstream release contains the fix.
    $batContent = Get-Content -LiteralPath $installBat -Raw
    if (-not $batContent.Contains("if not defined PIXI_CACHE_DIR")) {
        $patchedBat = $batContent
        $patchedBat = $patchedBat.Replace(
            "set `"PIXI_CACHE_DIR=%CD%\tmp\pixi-cache\windows`"",
            "if not defined PIXI_CACHE_DIR set `"PIXI_CACHE_DIR=%CD%\tmp\pixi-cache\windows`"")
        $patchedBat = $patchedBat.Replace(
            "set `"PIXI_PROJECT_ENVIRONMENT_DIR=%CD%\tmp\pixi-envs\windows`"",
            "if not defined PIXI_PROJECT_ENVIRONMENT_DIR set `"PIXI_PROJECT_ENVIRONMENT_DIR=%CD%\tmp\pixi-envs\windows`"")
        if ($patchedBat -ne $batContent) {
            Write-Utf8File -LiteralPath $installBat -Value $patchedBat
            Write-Host "Patched upstream install_windows.bat to honor pre-existing PIXI_*_DIR env vars."
        }
    }

    # Defensive patch for wgsextract-cli <= v0.3.5: setup_pacman_runtime.ps1 calls
    # `pacman -Sy` on a fresh MSYS2 install without initializing the keyring or
    # clearing the post-install db.lck. Replace the simple pacman call with a
    # robust sequence: trigger first-time init, wipe partial keyring, init+populate,
    # then call pacman with stale-lock cleanup + retries.
    $pacmanSetupPath = Join-Path $appDir "scripts\setup_pacman_runtime.ps1"
    if (Test-Path -LiteralPath $pacmanSetupPath -PathType Leaf) {
        $pacmanContent = Get-Content -LiteralPath $pacmanSetupPath -Raw
        $pacmanBuggyMarker = 'Invoke-Msys2Script ("pacman -Sy --needed --noconfirm " + ($Packages -join " "))'
        if ($pacmanContent.Contains($pacmanBuggyMarker) -and -not $pacmanContent.Contains("WGSEXTRACT-KEYRING-INIT")) {
            $pacmanReplacement = @'
# WGSEXTRACT-KEYRING-INIT (injected by gui-for-cli bundle patcher)
$gnupgRoot = Join-Path $Msys2Root "etc\pacman.d\gnupg"
    $marker = Join-Path $gnupgRoot ".wgsextract-keyring-ready"
    if (-not (Test-Path $marker)) {
        Write-Host "Triggering MSYS2 first-time initialization..."
        try { & $script:BashPath -lc "true" 2>&1 | Out-Host } catch { }
        Start-Sleep -Seconds 2
        $dbLock = Join-Path $Msys2Root "var\lib\pacman\db.lck"
        if (Test-Path $dbLock) { Remove-Item -LiteralPath $dbLock -Force -ErrorAction SilentlyContinue }
        if (Test-Path $gnupgRoot) { try { Remove-Item -LiteralPath $gnupgRoot -Recurse -Force -ErrorAction Stop } catch { } }
        Write-Host "Initializing MSYS2 pacman keyring..."
        Invoke-Msys2Script "pacman-key --init && pacman-key --populate msys2"
        New-Item -ItemType Directory -Force -Path (Split-Path $marker -Parent) | Out-Null
        Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o') -Encoding ASCII
    }
    $dbLock = Join-Path $Msys2Root "var\lib\pacman\db.lck"
    $pacmanCmd = "pacman -Sy --needed --noconfirm " + ($Packages -join " ")
    $attempts = 3
    for ($pacmanAttempt = 1; $pacmanAttempt -le $attempts; $pacmanAttempt += 1) {
        if (Test-Path $dbLock) { Remove-Item -LiteralPath $dbLock -Force -ErrorAction SilentlyContinue }
        try { Invoke-Msys2Script $pacmanCmd; break }
        catch {
            if ($pacmanAttempt -eq $attempts) { throw }
            $delay = 5 * $pacmanAttempt
            Write-Host "pacman command failed (attempt $pacmanAttempt/$attempts). Retrying in $delay s..."
            Start-Sleep -Seconds $delay
        }
    }
'@
            $pacmanContent = $pacmanContent.Replace($pacmanBuggyMarker, $pacmanReplacement)
            Write-Utf8File -LiteralPath $pacmanSetupPath -Value $pacmanContent
            Write-Host "Patched upstream setup_pacman_runtime.ps1 with robust MSYS2 keyring + pacman lock handling."
        }
    }

    # Redirect Pixi cache+envs to a short machine-local path to avoid Windows MAX_PATH
    # (260) issues when nested under the workspace. Tracked in install-manifest so the
    # uninstaller removes them.
    $pixiBaseDir = if ($env:WGSEXTRACT_PIXI_BASE_DIR) { $env:WGSEXTRACT_PIXI_BASE_DIR } else { Join-Path $env:LOCALAPPDATA "WGSExtractPixi" }
    $pixiCacheDirNew = Join-Path $pixiBaseDir "cache"
    $pixiEnvsDirNew = Join-Path $pixiBaseDir "envs"
    New-Item -ItemType Directory -Force -Path $pixiCacheDirNew, $pixiEnvsDirNew | Out-Null
    $env:PIXI_CACHE_DIR = $pixiCacheDirNew
    $env:PIXI_PROJECT_ENVIRONMENT_DIR = $pixiEnvsDirNew

    $env:MSYS2_ROOT = $msys2Root
    $batArgs = @()

    Write-Host "Delegating to upstream install_windows.bat (installs Pixi/MSYS2 as needed, pacman bio tools, BWA, and pacman runtime config)..."
    # Pre-install Pixi via api.github.com if it isn't already present. The
    # upstream installer downloads from github.com edge URLs which intermittently
    # 504; the API endpoint with octet-stream stays healthy.
    Install-PixiFromApi | Out-Null

    # Pre-download MSYS2 SFX via api.github.com and point the upstream
    # bootstrap at the local file. Same 504-bypass rationale as Pixi.
    if (-not $env:WGSEXTRACT_MSYS2_INSTALLER_URL) {
        $msys2SfxPath = Install-Msys2SfxFromApi -Msys2Root $msys2Root
        if ($msys2SfxPath) {
            $env:WGSEXTRACT_MSYS2_INSTALLER_URL = $msys2SfxPath
            Write-Host "Pointing upstream MSYS2 bootstrap at local SFX: $msys2SfxPath"
        }
    }

    Push-Location $appDir
    try {
        & $env:ComSpec /d /c "call `"$installBat`""
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }

    if (-not (Test-MsysInstall -Root $msys2Root)) {
        Write-Error "MSYS2 was not present at $msys2Root after install_windows.bat completed."
        exit 1
    }
    $pixi = Find-Pixi
    if (-not $pixi) {
        Write-Error "Pixi was not found on PATH or in ~\.pixi after install_windows.bat completed."
        exit 1
    }

    $shimPath = Join-Path $binDir "wgsextract.cmd"
    $runScript = Join-Path $scriptDir "run-wgsextract.ps1"
    Write-Utf8File -LiteralPath $shimPath -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$runScript"" %*`r`n"

    $manifestItems = New-Object System.Collections.Generic.List[object]
    if (-not $pixiPreInstalled) {
        $pixiBinDir = Split-Path -Parent $pixi
        $pixiInstallRoot = Split-Path -Parent $pixiBinDir
        if ($pixiInstallRoot) {
            $manifestItems.Add(@{ type = "directory"; path = $pixiInstallRoot; ownedBy = "install_windows.bat" })
        }
        if ($pixiBinDir) {
            $manifestItems.Add(@{ type = "userPathEntry"; path = $pixiBinDir; ownedBy = "install_windows.bat" })
        }
    }
    if (-not $msys2PreInstalled) {
        $manifestItems.Add(@{ type = "msys2Install"; root = $msys2Root; ownedBy = "install_windows.bat" })
    }
    if (Test-Path -LiteralPath $pixiBaseDir) {
        $manifestItems.Add(@{ type = "directory"; path = $pixiBaseDir; ownedBy = "setup-wgsextract-pixi.ps1" })
    }

    $manifestPath = Join-Path $installDir "install-manifest.json"
    $manifest = @{
        format = 1
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        wgsextractRef = $requestedRef
        items = $manifestItems
    }
    Set-Content -LiteralPath $manifestPath -Encoding UTF8 -Value ($manifest | ConvertTo-Json -Depth 5)

    Write-Host "WGS Extract CLI is installed in $installDir"
    exit 0
} finally {
}
