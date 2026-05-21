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

function Has-MapArguments {
    param([string[]]$Arguments)
    foreach ($argument in $Arguments) {
        if ($argument -in @("-M", "--map") -or $argument.StartsWith("-M=") -or $argument.StartsWith("--map=")) {
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

function Get-MappabilityMap {
    param([string]$Library, [string]$Alias)
    if (-not $Library) {
        return ""
    }
    if (Test-Path -LiteralPath $Library -PathType Leaf) {
        $Library = Split-Path -Parent $Library
    }
    $parent = Split-Path -Parent $Library
    $build = switch ($Alias) {
        "GRCh37" { "hg19" }
        "GRCh38" { "hg38" }
        default { return "" }
    }
    $directories = @(
        (Join-Path $Library "maps"),
        $Library,
        (Join-Path $Library "ref"),
        (Join-Path $Library "reference\maps"),
        (Join-Path $Library "reference"),
        (Join-Path $parent "maps"),
        $parent
    )
    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        foreach ($name in @("$build.map.gz", "$build.map", "$Alias.map.gz", "$Alias.map")) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
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
    $parent = Split-Path -Parent $Library
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
        (Join-Path $Library "reference\microarray"),
        $parent,
        (Join-Path $parent "ref"),
        (Join-Path $parent "microarray")
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

function Get-ReferenceFastaCandidates {
    param([string]$Directory)
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(fa|fasta)(\.gz)?$' } |
            Select-Object -ExpandProperty FullName
    )
}

function Select-ReferenceFasta {
    param([string[]]$Candidates, [string]$Alias)
    if ($Candidates.Count -eq 0) {
        return ""
    }
    $patterns = switch ($Alias) {
        "GRCh37" { @("hg19", "hg37", "grch37", "hs37") }
        "GRCh38" { @("hg38", "grch38", "hs38") }
        default { @() }
    }
    foreach ($pattern in $patterns) {
        foreach ($candidate in $Candidates) {
            if ([System.IO.Path]::GetFileName($candidate).ToLowerInvariant().Contains($pattern)) {
                return $candidate
            }
        }
    }
    if ($Candidates.Count -eq 1) {
        return $Candidates[0]
    }
    return ""
}

function Resolve-ReferenceFasta {
    param([string]$Reference, [string]$InputPath, [string]$Alias)

    if ($Reference -and (Test-Path -LiteralPath $Reference -PathType Leaf) -and $Reference -match '\.(fa|fasta)(\.gz)?$') {
        return $Reference
    }

    $referenceCandidates = @()
    if ($Reference -and (Test-Path -LiteralPath $Reference -PathType Container)) {
        $referenceCandidates += Get-ReferenceFastaCandidates -Directory $Reference
        $referenceCandidates += Get-ReferenceFastaCandidates -Directory (Join-Path $Reference "genomes")
    }
    $referenceFasta = Select-ReferenceFasta -Candidates $referenceCandidates -Alias $Alias
    if ($referenceFasta) {
        return $referenceFasta
    }

    if ($InputPath) {
        $inputDirectory = Split-Path -Parent $InputPath
        $inputFasta = Select-ReferenceFasta -Candidates (Get-ReferenceFastaCandidates -Directory $inputDirectory) -Alias $Alias
        if ($inputFasta) {
            return $inputFasta
        }
    }

    return $Reference
}

function Set-ArgumentValue {
    param([string[]]$Arguments, [string]$Name, [string]$Value)

    $updated = @()
    $replaced = $false
    for ($index = 0; $index -lt $Arguments.Count; $index += 1) {
        $argument = $Arguments[$index]
        if ($argument -eq $Name) {
            $updated += $argument
            if ($index + 1 -lt $Arguments.Count) {
                $updated += $Value
                $index += 1
            } else {
                $updated += $Value
            }
            $replaced = $true
            continue
        }
        if ($argument.StartsWith("$Name=")) {
            $updated += "$Name=$Value"
            $replaced = $true
            continue
        }
        $updated += $argument
    }
    if (-not $replaced) {
        $updated += @($Name, $Value)
    }
    return $updated
}

if ($args.Count -lt 1) {
    Write-Error "Usage: run-wgsextract-vcf.ps1 VCF_SUBCOMMAND [ARG...]"
    exit 64
}

$subcommand = $args[0]
if ($subcommand -notin @("snp", "indel", "cnv")) {
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
$resolvedRefPath = Resolve-ReferenceFasta -Reference $refPath -InputPath $inputPath -Alias $alias
$forwardArgs = if ($resolvedRefPath -and $resolvedRefPath -ne $refPath) {
    Set-ArgumentValue -Arguments $args -Name "--ref" -Value $resolvedRefPath
} else {
    @($args)
}
$effectiveRefPath = if ($resolvedRefPath) { $resolvedRefPath } else { $refPath }

if ($subcommand -eq "cnv" -and -not (Has-MapArguments -Arguments $args)) {
    $mapFile = Get-MappabilityMap -Library $effectiveRefPath -Alias $alias
    if (-not $mapFile -and $effectiveRefPath -ne $refPath) {
        $mapFile = Get-MappabilityMap -Library $refPath -Alias $alias
    }
    if ($mapFile) {
        $forwardArgs += @("--map", $mapFile)
    }
}

if (Has-PloidyArguments -Arguments $forwardArgs) {
    & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @forwardArgs
    exit $LASTEXITCODE
}

if ($alias) {
    $ploidyFile = Get-PloidyFile -Library $effectiveRefPath -Alias $alias
    if (-not $ploidyFile -and $effectiveRefPath -ne $refPath) {
        $ploidyFile = Get-PloidyFile -Library $refPath -Alias $alias
    }
    if ($ploidyFile) {
        & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @forwardArgs --ploidy-file $ploidyFile
        exit $LASTEXITCODE
    }
    & (Join-Path $scriptDir "run-wgsextract.ps1") vcf @forwardArgs --ploidy $alias
    exit $LASTEXITCODE
}

& (Join-Path $scriptDir "run-wgsextract.ps1") vcf @forwardArgs
exit $LASTEXITCODE
