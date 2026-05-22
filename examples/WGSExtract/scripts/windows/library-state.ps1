$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$refPath = if ($args.Count -gt 0 -and $args[0]) { $args[0] } else { $env:GUI_FOR_CLI_FIELD_ref_path }
$genomeLibrary = if ($args.Count -gt 1 -and $args[1]) { $args[1] } else { $env:GUI_FOR_CLI_FIELD_genome_library }
if (-not $genomeLibrary) {
    $genomeLibrary = $env:GUI_FOR_CLI_CONFIG_genome_library
}
if (-not $genomeLibrary) {
    $genomeLibrary = $env:GUI_FOR_CLI_CONFIG_wgs_settings_genome_library
}

$statusArgs = @("ref", "status", "--values")
if ($refPath) {
    $statusArgs += @("--ref", $refPath)
}
if ($genomeLibrary) {
    $statusArgs += @("--genome-library", $genomeLibrary)
}
if ($env:GUI_FOR_CLI_FIELD_vcf_ann_vcf) {
    $statusArgs += @("--annotation-vcf", $env:GUI_FOR_CLI_FIELD_vcf_ann_vcf)
}
if ($env:GUI_FOR_CLI_FIELD_vcf_path) {
    $statusArgs += @("--input", $env:GUI_FOR_CLI_FIELD_vcf_path)
}

& (Join-Path $scriptDir "run-wgsextract.ps1") @statusArgs
exit $LASTEXITCODE
