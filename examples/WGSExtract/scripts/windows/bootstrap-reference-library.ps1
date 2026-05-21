$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }

function Merge-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        if ($_.Name.StartsWith("._") -or $_.Name -eq ".DS_Store") {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
            return
        }
        $target = Join-Path $Destination $_.Name
        if ($_.PSIsContainer) {
            Merge-Directory -Source $_.FullName -Destination $target
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        } elseif (-not (Test-Path -LiteralPath $target)) {
            Move-Item -LiteralPath $_.FullName -Destination $target
        } elseif ($_.Length -eq (Get-Item -LiteralPath $target).Length -and (Get-FileHash -LiteralPath $_.FullName).Hash -eq (Get-FileHash -LiteralPath $target).Hash) {
            Remove-Item -LiteralPath $_.FullName -Force
        } else {
            Write-Warning "Leaving duplicate bootstrap file in place: $($_.FullName)"
        }
    }
}

function Normalize-BootstrapLayout {
    $nested = Join-Path $referenceLibrary "reference"
    if (Test-Path -LiteralPath $nested -PathType Container) {
        Merge-Directory -Source $nested -Destination $referenceLibrary
        Get-ChildItem -LiteralPath $nested -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            Remove-Item -Force
        if (-not (Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $nested -Force
        }
    }
}

function Install-PloidyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$Output
    )
    if (Test-Path -LiteralPath $Output -PathType Leaf) {
        Write-Host "Ploidy file already installed: $Output"
        return
    }
    Write-Host "Installing ploidy file for ${Alias}: $Output"
    $tmpDirectory = Split-Path -Parent $Output
    $tmpPrefix = Split-Path -Leaf $Output
    $unique = ([guid]::NewGuid()).ToString("N")
    $tmp = Join-Path $tmpDirectory "$tmpPrefix.$unique.tmp"
    $stdoutTmp = Join-Path $tmpDirectory "$tmpPrefix.$unique.stdout.tmp"
    $stderrTmp = Join-Path $tmpDirectory "$tmpPrefix.$unique.stderr.tmp"
    $wroteTemp = $false
    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativePreference = $null
    $hasNativePreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hasNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }
    try {
        $ErrorActionPreference = "Continue"
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $powerShell = (Get-Process -Id $PID).Path
        Remove-Item -LiteralPath $stdoutTmp, $stderrTmp -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath $powerShell -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            (Join-Path $scriptDir "run-wgsextract-env.ps1"),
            "bcftools",
            "call",
            "--ploidy",
            "${Alias}?"
        ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutTmp -RedirectStandardError $stderrTmp | Out-Null
        $outputLines = @()
        if (Test-Path -LiteralPath $stdoutTmp -PathType Leaf) {
            $outputLines += Get-Content -LiteralPath $stdoutTmp
        }
        if (Test-Path -LiteralPath $stderrTmp -PathType Leaf) {
            $outputLines += Get-Content -LiteralPath $stderrTmp
        }
        [System.IO.File]::WriteAllLines(
            $tmp,
            [string[]]$outputLines,
            [System.Text.UTF8Encoding]::new($false)
        )
        $wroteTemp = $true
    } finally {
        Remove-Item -LiteralPath $stdoutTmp, $stderrTmp -Force -ErrorAction SilentlyContinue
        if (-not $wroteTemp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not (Test-Path -LiteralPath $tmp -PathType Leaf) -or -not (Select-String -LiteralPath $tmp -Pattern "^\*" -Quiet)) {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Get-Content -LiteralPath $tmp | Write-Error
            Remove-Item -LiteralPath $tmp -Force
        }
        exit 1
    }
    Move-Item -Force -LiteralPath $tmp -Destination $Output
    Write-Host "Installed ploidy file: $Output"
}

function Invoke-DownloadIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Output,
        [Parameter(Mandatory = $true)][string]$Sha256
    )
    if (Test-Path -LiteralPath $Output -PathType Leaf) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash.ToLowerInvariant()
        if ($actual -eq $Sha256) {
            return
        }
        Write-Warning "Checksum mismatch for $Output; re-downloading."
        Remove-Item -LiteralPath $Output -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
    $tmp = "$Output.$(([guid]::NewGuid()).ToString("N")).tmp"
    for ($attempt = 1; $attempt -le 3; $attempt += 1) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmp).Hash.ToLowerInvariant()
            if ($actual -ne $Sha256) {
                throw "Checksum mismatch for downloaded file: $Url"
            }
            Move-Item -Force -LiteralPath $tmp -Destination $Output
            return
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            if ($attempt -eq 3) {
                throw
            }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Install-MappabilityMaps {
    $requiredFiles = @(
        "hg19.map.gz",
        "hg19.map.gz.fai",
        "hg19.map.gz.gzi",
        "hg38.map.gz",
        "hg38.map.gz.fai",
        "hg38.map.gz.gzi"
    )
    $mapsDir = Join-Path $referenceLibrary "maps"
    New-Item -ItemType Directory -Force -Path $mapsDir | Out-Null
    $missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $mapsDir $_) -PathType Leaf) })
    if ($missing.Count -eq 0) {
        return
    }

    $archive = Join-Path $referenceLibrary "wgsextract-delly-mappability-maps.$(([guid]::NewGuid()).ToString("N")).zip.tmp"
    $extractDir = Join-Path $referenceLibrary "mappability-maps.$(([guid]::NewGuid()).ToString("N")).tmp"
    try {
        Invoke-DownloadIfMissing `
            -Url "https://github.com/theontho/wgsextract-cli/releases/download/v0.1.0/wgsextract-delly-mappability-maps.zip" `
            -Output $archive `
            -Sha256 "cab55d8fe28f3c0da90cfdd0a8a4951dc5a33d182bbce3ef34392762eafe5d1b"
        Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
        foreach ($fileName in $requiredFiles) {
            $source = Join-Path $extractDir "maps\$fileName"
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Mappability map archive is missing maps\$fileName"
            }
            Copy-Item -LiteralPath $source -Destination (Join-Path $mapsDir $fileName) -Force
        }
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-MappabilityMapsOptional {
    if ($env:WGSEXTRACT_SKIP_MAPPABILITY_MAPS -eq "1") {
        Write-Host "Skipping optional mappability maps."
        return
    }
    if ($env:WGSEXTRACT_INSTALL_MAPPABILITY_MAPS -ne "1") {
        Write-Host "Skipping optional mappability map downloads during setup. Set WGSEXTRACT_INSTALL_MAPPABILITY_MAPS=1 to preinstall them."
        return
    }
    try {
        Write-Host "Downloading optional mappability maps..."
        Install-MappabilityMaps
        Write-Host "Optional mappability maps are installed."
    } catch {
        Write-Warning "Failed to install mappability maps; continuing without auto-map support. $($_.Exception.Message)"
    }
}

function Test-BootstrapSupportAssets {
    if (-not (Test-Path -LiteralPath $referenceLibrary -PathType Container)) {
        return $false
    }
    $content = Get-ChildItem -LiteralPath $referenceLibrary -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "All_SNPs*.tab.gz" -or $_.Name -like "All_SNPs*.vcf.gz" -or $_.Name -like "snps_*.vcf.gz" -or $_.Name -eq "common_all.vcf.gz" } |
        Select-Object -First 1
    return $null -ne $content
}

function Install-BootstrapSupportFiles {
    Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
    Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
    Install-MappabilityMapsOptional
    Write-Host "Reference bootstrap support files are ready."
}

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
Normalize-BootstrapLayout
if (Test-BootstrapSupportAssets) {
    Install-BootstrapSupportFiles
    exit 0
}

$runner = Join-Path $scriptDir "run-wgsextract.ps1"
for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    & $runner ref bootstrap --ref $referenceLibrary
    if ($LASTEXITCODE -eq 0) {
        Normalize-BootstrapLayout
        Install-BootstrapSupportFiles
        exit 0
    }
    if ($attempt -lt 3) {
        Start-Sleep -Seconds (2 * $attempt)
    }
}
exit $LASTEXITCODE
