$ErrorActionPreference = "Stop"

if ($args.Count -lt 2) {
    Write-Error "Usage: repair-ftdna-vcf.ps1 INPUT_VCF OUTPUT_DIR"
    exit 64
}

$inputPath = $args[0]
$outDir = if ($args[1]) { $args[1] } else { Split-Path -Parent $inputPath }
$scriptDir = Split-Path -Parent $PSCommandPath
$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"
$runner = Join-Path $scriptDir "run-wgsextract.ps1"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$name = [System.IO.Path]::GetFileName($inputPath)
$baseName = if ($name.EndsWith(".vcf.gz", [System.StringComparison]::OrdinalIgnoreCase)) {
    $name.Substring(0, $name.Length - 7)
} else {
    [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
}

& $runtime bcftools view $inputPath |
    & $runner repair ftdna-vcf |
    Set-Content -Path (Join-Path $outDir "${baseName}_repaired.vcf")
exit $LASTEXITCODE
