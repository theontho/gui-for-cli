$ErrorActionPreference = "Stop"

if ($args.Count -lt 1) {
    Write-Error "Usage: repair-ftdna-bam.ps1 INPUT_BAM_OR_CRAM [OUTPUT_DIR]"
    exit 64
}

$inputPath = $args[0]
$outDir = if ($args.Count -gt 1 -and $args[1]) { $args[1] } else { Split-Path -Parent $inputPath }
$scriptDir = Split-Path -Parent $PSCommandPath
$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"
$runner = Join-Path $scriptDir "run-wgsextract.ps1"
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    Write-Error "Input BAM/CRAM does not exist: $inputPath"
    exit 66
}
foreach ($requiredScript in @($runtime, $runner)) {
    if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
        Write-Error "Required script does not exist: $requiredScript"
        exit 66
    }
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)

& $runtime samtools view -h $inputPath |
    & $runner repair ftdna-bam |
    & $runtime samtools view -b -o (Join-Path $outDir "${baseName}_repaired.bam") -
exit $LASTEXITCODE
