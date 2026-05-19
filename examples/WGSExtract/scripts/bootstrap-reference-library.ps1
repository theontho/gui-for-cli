$ErrorActionPreference = "Stop"

$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }

function Merge-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        $target = Join-Path $Destination $_.Name
        if ($_.PSIsContainer) {
            Merge-Directory -Source $_.FullName -Destination $target
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        } elseif (-not (Test-Path -LiteralPath $target)) {
            Move-Item -LiteralPath $_.FullName -Destination $target
        } else {
            Write-Warning "Leaving duplicate bootstrap file in place: $($_.FullName)"
        }
    }
}

function Normalize-BootstrapLayout {
    $nested = Join-Path $referenceLibrary "reference"
    if (Test-Path -LiteralPath $nested -PathType Container) {
        Merge-Directory -Source $nested -Destination $referenceLibrary
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
    & (Join-Path $bundleRoot "scripts\run-wgsextract-env.ps1") bcftools call --ploidy "$Alias?" | Set-Content -LiteralPath $tmp
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    Move-Item -Force -LiteralPath $tmp -Destination $Output
}

New-Item -ItemType Directory -Force -Path $referenceLibrary | Out-Null
& (Join-Path $bundleRoot "scripts\run-wgsextract.ps1") ref bootstrap --ref $referenceLibrary
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
Normalize-BootstrapLayout
Install-PloidyFile -Alias "GRCh37" -Output (Join-Path $referenceLibrary "ploidy_hg19.txt")
Install-PloidyFile -Alias "GRCh38" -Output (Join-Path $referenceLibrary "ploidy_hg38.txt")
