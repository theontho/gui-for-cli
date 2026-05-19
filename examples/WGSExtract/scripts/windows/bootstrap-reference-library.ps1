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
        } elseif ((Get-FileHash -LiteralPath $_.FullName).Hash -eq (Get-FileHash -LiteralPath $target).Hash) {
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
    $tmp = "$Output.tmp"
    & (Join-Path $scriptDir "run-wgsextract-env.ps1") bcftools call --ploidy "$Alias?" 2>&1 | Set-Content -LiteralPath $tmp
    if (-not (Test-Path -LiteralPath $tmp -PathType Leaf) -or -not (Select-String -LiteralPath $tmp -Pattern "^\*" -Quiet)) {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Get-Content -LiteralPath $tmp | Write-Error
            Remove-Item -LiteralPath $tmp -Force
        }
        exit 1
    }
    Move-Item -Force -LiteralPath $tmp -Destination $Output
}

function Test-BootstrapContent {
    if (-not (Test-Path -LiteralPath $referenceLibrary -PathType Container)) {
        return $false
    }
    $content = Get-ChildItem -LiteralPath $referenceLibrary -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "._*" -and $_.Name -ne ".DS_Store" -and $_.Name -notlike "ploidy_*.txt" } |
        Select-Object -First 1
    return $null -ne $content
}

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
Normalize-BootstrapLayout
if (Test-BootstrapContent) {
    Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
    Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
    exit 0
}

$runner = Join-Path $scriptDir "run-wgsextract.ps1"
for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    & $runner ref bootstrap --ref $referenceLibrary
    if ($LASTEXITCODE -eq 0) {
        Normalize-BootstrapLayout
        Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
        Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
        exit 0
    }
    if ($attempt -lt 3) {
        Start-Sleep -Seconds (2 * $attempt)
    }
}
exit $LASTEXITCODE
