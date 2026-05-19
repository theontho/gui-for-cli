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
        return
    }
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
    $mapsDir = Join-Path $referenceLibrary "maps"
    New-Item -ItemType Directory -Force -Path $mapsDir | Out-Null
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz" `
        -Output (Join-Path $mapsDir "hg19.map.gz") `
        -Sha256 "8336a5df4d84be06aebe43d3b5ad8dac8c77b20a9f5607124b6b39c69536a366"
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz.fai" `
        -Output (Join-Path $mapsDir "hg19.map.gz.fai") `
        -Sha256 "0afa4180c7ed5a5d2046a2c44deea7f772bba5ff0934823e7de39e101c3aa99b"
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz.gzi" `
        -Output (Join-Path $mapsDir "hg19.map.gz.gzi") `
        -Sha256 "dcbbc88e0d24cead9959cbff226a3f49557c35e0eb928d43551404958b84b2eb"
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz" `
        -Output (Join-Path $mapsDir "hg38.map.gz") `
        -Sha256 "bcc9c9a58ea28b4c0e68ef387b049b174acbb30f01935224d071c1d7492638c7"
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz.fai" `
        -Output (Join-Path $mapsDir "hg38.map.gz.fai") `
        -Sha256 "15312f85f6ff6a975cc3ecbb6106b44eb8d3be1e8a22b89ef327458900081d52"
    Invoke-DownloadIfMissing `
        -Url "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz.gzi" `
        -Output (Join-Path $mapsDir "hg38.map.gz.gzi") `
        -Sha256 "41f4447d2d6e18a8c8b38919f553002bc134a57619244674725cbfd3179ce4a4"
}

function Install-MappabilityMapsOptional {
    try {
        Install-MappabilityMaps
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

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
Normalize-BootstrapLayout
if (Test-BootstrapSupportAssets) {
    Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
    Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
    Install-MappabilityMapsOptional
    exit 0
}

$runner = Join-Path $scriptDir "run-wgsextract.ps1"
for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    & $runner ref bootstrap --ref $referenceLibrary
    if ($LASTEXITCODE -eq 0) {
        Normalize-BootstrapLayout
        Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
        Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
        Install-MappabilityMapsOptional
        exit 0
    }
    if ($attempt -lt 3) {
        Start-Sleep -Seconds (2 * $attempt)
    }
}
exit $LASTEXITCODE
