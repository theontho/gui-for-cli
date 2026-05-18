$ErrorActionPreference = "Stop"

$refPath = if ($args.Count -gt 0) { $args[0] } else { $env:GUI_FOR_CLI_FIELD_ref_path }
$geneMapInstalled = $false
$libraryBootstrapped = $false

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

@{
    values = @{
        "library.geneMapInstalled" = $geneMapInstalled.ToString().ToLowerInvariant()
        "library.isBootstrapped" = $libraryBootstrapped.ToString().ToLowerInvariant()
    }
} | ConvertTo-Json -Compress
