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
    Write-Host "Running: bcftools call --ploidy ${Alias}? (this may take a moment while Pixi starts the bundled environment)"
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
        $process = Start-Process -FilePath $powerShell -ArgumentList @(
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            (Join-Path $scriptDir "run-wgsextract-env.ps1"),
            "bcftools",
            "call",
            "--ploidy",
            "${Alias}?"
        ) -NoNewWindow -PassThru -RedirectStandardOutput $stdoutTmp -RedirectStandardError $stderrTmp
        $startedAt = Get-Date
        while (-not $process.WaitForExit(5000)) {
            $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds)
            Write-Host "Still generating ${Alias} ploidy file after ${elapsed}s (pid $($process.Id)); waiting for bcftools/Pixi..."
        }
        if ($process.ExitCode -ne 0) {
            Write-Host "bcftools ploidy lookup for ${Alias} exited with code $($process.ExitCode); checking captured output for usable ploidy data."
        }
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

function Should-InstallMappabilityMaps {
    return $env:WGSEXTRACT_SKIP_MAPPABILITY_MAPS -ne "1"
}

function Write-MappabilityMapsStatus {
    if (Should-InstallMappabilityMaps) {
        Write-Host "Mappability maps are part of setup; wgsextract ref bootstrap handles them with --install-mappability-maps."
    } else {
        Write-Host "Skipping mappability map installation because WGSEXTRACT_SKIP_MAPPABILITY_MAPS=1."
    }
}

function Invoke-ReferenceBootstrap {
    $runner = Join-Path $scriptDir "run-wgsextract.ps1"
    $bootstrapArgs = @("ref", "bootstrap", "--ref", $referenceLibrary)
    if (Should-InstallMappabilityMaps) {
        $bootstrapArgs += "--install-mappability-maps"
        Write-Host "Running reference bootstrap with mappability maps enabled."
    } else {
        Write-Host "Running reference bootstrap without mappability maps."
    }
    & $runner @bootstrapArgs
    $script:BootstrapExitCode = $LASTEXITCODE
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
    Write-MappabilityMapsStatus
    Write-Host "Reference bootstrap support files are ready."
}

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
Normalize-BootstrapLayout
if (Test-BootstrapSupportAssets) {
    if (Should-InstallMappabilityMaps) {
        Invoke-ReferenceBootstrap
        if ($script:BootstrapExitCode -ne 0) {
            exit $script:BootstrapExitCode
        }
        Normalize-BootstrapLayout
    }
    Install-BootstrapSupportFiles
    exit 0
}

for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    Invoke-ReferenceBootstrap
    if ($script:BootstrapExitCode -eq 0) {
        Normalize-BootstrapLayout
        Install-BootstrapSupportFiles
        exit 0
    }
    if ($attempt -lt 3) {
        Start-Sleep -Seconds (2 * $attempt)
    }
}
exit $script:BootstrapExitCode
