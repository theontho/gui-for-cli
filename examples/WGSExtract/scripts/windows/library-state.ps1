$ErrorActionPreference = "Stop"

$refPath = if ($args.Count -gt 0 -and $args[0]) { $args[0] } else { $env:GUI_FOR_CLI_FIELD_ref_path }
$genomeLibrary = if ($args.Count -gt 1 -and $args[1]) { $args[1] } else { $env:GUI_FOR_CLI_FIELD_genome_library }
if (-not $genomeLibrary) {
    $genomeLibrary = $env:GUI_FOR_CLI_CONFIG_genome_library
}
if (-not $genomeLibrary) {
    $genomeLibrary = $env:GUI_FOR_CLI_CONFIG_wgs_settings_genome_library
}
if (-not $genomeLibrary) {
    $workspace = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
    $genomeLibrary = Join-Path $workspace "genomes"
}

$geneMapInstalled = $false
$libraryBootstrapped = $false
$testGenomeInstalled = $false
$testGenomeStatus = "missing"
$testGenomePath = Join-Path $genomeLibrary "wgsextract-benchmark-hg19-mini"
$annotationVcfFile = ""
$spliceaiFile = ""
$alphamissenseFile = ""
$pharmgkbFile = ""
$customAnnotationVcf = $env:GUI_FOR_CLI_FIELD_vcf_ann_vcf
$inputVcf = $env:GUI_FOR_CLI_FIELD_vcf_path

function Get-BuildHint {
    param([string[]]$Values)

    $combined = ($Values -join " ").ToLowerInvariant()
    if ($combined -match "hg38|grch38|hs38") {
        return "hg38"
    }
    if ($combined -match "hg19|grch37|hs37") {
        return "hg19"
    }
    return ""
}

function Get-FirstExistingNamedFile {
    param(
        [string[]]$Directories,
        [string[]]$Names
    )

    foreach ($directory in $Directories) {
        if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        foreach ($name in $Names) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
    return ""
}

function Get-FirstExistingPatternFile {
    param(
        [string[]]$Directories,
        [string[]]$Patterns
    )

    foreach ($directory in $Directories) {
        if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        foreach ($pattern in $Patterns) {
            $match = Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $pattern } |
                Sort-Object Name |
                Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }
    return ""
}

if ($refPath) {
    $refDir = Join-Path $refPath "ref"
    $geneMapInstalled = (Test-Path -LiteralPath (Join-Path $refDir "genes_hg19.tsv") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $refDir "genes_hg38.tsv") -PathType Leaf)

    if (Test-Path -LiteralPath $refPath -PathType Container) {
        $libraryBootstrapped = [bool](Get-ChildItem -LiteralPath $refPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @("genes_hg19.tsv", "genes_hg38.tsv", ".DS_Store") } |
            Select-Object -First 1)
    }

    $annotationDirs = @(
        $refPath,
        (Join-Path $refPath "ref"),
        (Join-Path $refPath "microarray"),
        (Join-Path $refPath "genomes\microarray")
    )
    $annotationVcfFile = Get-FirstExistingNamedFile -Directories $annotationDirs -Names @(
        "All_SNPs.vcf.gz",
        "common_all.vcf.gz",
        "snps_hg19.vcf.gz",
        "snps_hg38.vcf.gz",
        "snps_grch37.vcf.gz",
        "snps_grch38.vcf.gz",
        "All_SNPs_hg19_ref.tab.gz",
        "All_SNPs_hg38_ref.tab.gz",
        "All_SNPs_HG19_ref.tab.gz",
        "All_SNPs_HG38_ref.tab.gz",
        "All_SNPs_GRCh37_ref.tab.gz",
        "All_SNPs_GRCh38_ref.tab.gz",
        "All_SNPs_grch37_ref.tab.gz",
        "All_SNPs_grch38_ref.tab.gz"
    )
    $refDirs = @($refPath, (Join-Path $refPath "ref"))
    $buildHint = Get-BuildHint -Values @($inputVcf, $refPath)
    $spliceaiPatterns = @()
    $alphamissensePatterns = @()
    $pharmgkbPatterns = @()
    if ($buildHint) {
        $spliceaiPatterns += @("spliceai*$buildHint*.vcf.gz", "spliceai*$buildHint*.vcf.bgz")
        $alphamissensePatterns += @("alphamissense*$buildHint*.tsv.gz", "alphamissense*$buildHint*.vcf.gz", "alphamissense*$buildHint*.vcf.bgz")
        $pharmgkbPatterns += @("pharmgkb*$buildHint*.vcf.gz", "pharmgkb*$buildHint*.vcf.bgz", "pharmgkb*$buildHint*.tsv.gz")
    }
    $spliceaiPatterns += @("spliceai*.vcf.gz", "spliceai*.vcf.bgz")
    $alphamissensePatterns += @("alphamissense*.tsv.gz", "alphamissense*.vcf.gz", "alphamissense*.vcf.bgz")
    $pharmgkbPatterns += @("pharmgkb*.vcf.gz", "pharmgkb*.vcf.bgz", "pharmgkb*.tsv.gz")
    $spliceaiFile = Get-FirstExistingPatternFile -Directories $refDirs -Patterns $spliceaiPatterns
    $alphamissenseFile = Get-FirstExistingPatternFile -Directories $refDirs -Patterns $alphamissensePatterns
    $pharmgkbFile = Get-FirstExistingPatternFile -Directories $refDirs -Patterns $pharmgkbPatterns
}

if ((Test-Path -LiteralPath $testGenomePath -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $testGenomePath "genome-config.toml") -PathType Leaf)) {
    $testGenomeInstalled = $true
    $testGenomeStatus = "installed"
} elseif (Test-Path -LiteralPath (Join-Path $genomeLibrary ".downloads\wgsextract-benchmark-hg19-mini.zip.partial") -PathType Leaf) {
    $testGenomeStatus = "incomplete"
}

@{
    values = @{
        "library.geneMapInstalled" = $geneMapInstalled.ToString().ToLowerInvariant()
        "library.isBootstrapped" = $libraryBootstrapped.ToString().ToLowerInvariant()
        "library.annotationVcfInstalled" = ([bool]$annotationVcfFile).ToString().ToLowerInvariant()
        "library.annotationVcfFile" = $annotationVcfFile
        "library.annotationVcfArgument" = if ($customAnnotationVcf) { $customAnnotationVcf } else { $annotationVcfFile }
        "library.annotationVcfReady" = (($customAnnotationVcf) -or ($annotationVcfFile)).ToString().ToLowerInvariant()
        "library.spliceaiInstalled" = ([bool]$spliceaiFile).ToString().ToLowerInvariant()
        "library.spliceaiFile" = $spliceaiFile
        "library.alphamissenseInstalled" = ([bool]$alphamissenseFile).ToString().ToLowerInvariant()
        "library.alphamissenseFile" = $alphamissenseFile
        "library.pharmgkbInstalled" = ([bool]$pharmgkbFile).ToString().ToLowerInvariant()
        "library.pharmgkbFile" = $pharmgkbFile
        "library.testGenomeInstalled" = $testGenomeInstalled.ToString().ToLowerInvariant()
        "library.testGenomeStatus" = $testGenomeStatus
        "library.testGenomePath" = $testGenomePath
    }
} | ConvertTo-Json -Compress
