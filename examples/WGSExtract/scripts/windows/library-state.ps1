$ErrorActionPreference = "Stop"

$refPath = if ($args.Count -gt 0) { $args[0] } else { $env:GUI_FOR_CLI_FIELD_ref_path }
$genomeLibrary = if ($args.Count -gt 1) { $args[1] } else { $env:GUI_FOR_CLI_FIELD_genome_library }
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

if ($refPath) {
    $refDir = Join-Path $refPath "ref"
    $geneMapInstalled = (Test-Path -LiteralPath (Join-Path $refDir "genes_hg19.tsv") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $refDir "genes_hg38.tsv") -PathType Leaf)

    if (Test-Path -LiteralPath $refPath -PathType Container) {
        $libraryBootstrapped = [bool](Get-ChildItem -LiteralPath $refPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @("genes_hg19.tsv", "genes_hg38.tsv", ".DS_Store") } |
            Select-Object -First 1)
    }
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
        "library.testGenomeInstalled" = $testGenomeInstalled.ToString().ToLowerInvariant()
        "library.testGenomeStatus" = $testGenomeStatus
        "library.testGenomePath" = $testGenomePath
    }
} | ConvertTo-Json -Compress
