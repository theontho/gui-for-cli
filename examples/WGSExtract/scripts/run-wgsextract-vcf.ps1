$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath

function Get-ArgumentValue {
    param([string]$Name, [string[]]$Arguments)
    for ($index = 0; $index -lt $Arguments.Count; $index += 1) {
        $argument = $Arguments[$index]
        if ($argument -eq $Name -and $index + 1 -lt $Arguments.Count) {
            return $Arguments[$index + 1]
        }
        if ($argument.StartsWith("$Name=")) {
            return $argument.Substring($Name.Length + 1)
        }
    }
    return ""
}

function Has-PloidyArguments {
    param([string[]]$Arguments)
    foreach ($argument in $Arguments) {
        if ($argument -in @("--ploidy", "--ploidy-file") -or $argument.StartsWith("--ploidy=") -or $argument.StartsWith("--ploidy-file=")) {
            return $true
        }
    }
    return $false
}

function Get-PloidyAlias {
    param([string[]]$Values)
    foreach ($value in $Values) {
        $lower = "$value".ToLowerInvariant()
        if ($lower -match "hg19|hg37|grch37|hs37") {
            return "GRCh37"
        }
        if ($lower -match "hg38|grch38|hs38") {
            return "GRCh38"
        }
    }
    return ""
}

function Get-PloidyFile {
    param([string]$Library, [string]$Alias)
    if (-not $Library) {
        return ""
    }
    if (Test-Path -LiteralPath $Library -PathType Leaf) {
        $Library = Split-Path -Parent $Library
    }
    $build = switch ($Alias) {
        "GRCh37" { "hg19" }
        "GRCh38" { "hg38" }
        default { return "" }
    }
    $directories = @(
        $Library,
        (Join-Path $Library "ref"),
        (Join-Path $Library "microarray"),
        (Join-Path $Library "reference"),
        (Join-Path $Library "reference\ref"),
        (Join-Path $Library "reference\microarray")
    )
    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        foreach ($name in @("ploidy_$build.txt", "ploidy_$Alias.txt", "ploidy.txt")) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
    return ""
}

if ($args.Count -lt 1) {
    Write-Error "Usage: run-wgsextract-vcf.ps1 VCF_SUBCOMMAND [ARG...]"
    exit 64
}

$subcommand = $args[0]
if ($subcommand -notin @("snp", "indel")) {
    & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @args
    exit $LASTEXITCODE
}

if (Has-PloidyArguments -Arguments $args) {
    & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @args
    exit $LASTEXITCODE
}

$refPath = Get-ArgumentValue -Name "--ref" -Arguments $args
$inputPath = Get-ArgumentValue -Name "--input" -Arguments $args
$alias = Get-PloidyAlias -Values @(
    $refPath,
    $inputPath,
    $env:GUI_FOR_CLI_FIELD_ref_fasta,
    $env:GUI_FOR_CLI_CONFIG_reference_fasta,
    $env:GUI_FOR_CLI_CONFIG_wgs_settings_ref_fasta,
    $env:GUI_FOR_CLI_CONFIG_wgs_settings_reference_fasta
)

if ($alias) {
    $ploidyFile = Get-PloidyFile -Library $refPath -Alias $alias
    if ($ploidyFile) {
        & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @args --ploidy-file $ploidyFile
        exit $LASTEXITCODE
    }
    & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @args --ploidy $alias
    exit $LASTEXITCODE
}

& (Join-Path $scriptDir "run-wgsextract.ps1") vcf @args
exit $LASTEXITCODE
