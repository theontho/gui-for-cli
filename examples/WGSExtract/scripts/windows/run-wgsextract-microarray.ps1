$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$forwardArgs = @($args)
if ($forwardArgs.Count -gt 0 -and $forwardArgs[0] -eq "microarray") {
    $forwardArgs = @($forwardArgs | Select-Object -Skip 1)
}

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

function Has-Argument {
    param([string]$Name, [string[]]$Arguments)
    foreach ($argument in $Arguments) {
        if ($argument -eq $Name -or $argument.StartsWith("$Name=")) {
            return $true
        }
    }
    return $false
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

function Get-InputStem {
    param([string]$Path)
    $name = Split-Path -Leaf $Path
    foreach ($extension in @(".vcf.gz", ".bam", ".cram", ".vcf", ".bcf")) {
        if ($name.EndsWith($extension, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $name.Substring(0, $name.Length - $extension.Length)
        }
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($name)
}

function Get-FirstExistingFile {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return ""
}

function Get-SingleMatchingFile {
    param(
        [string]$Directory,
        [string[]]$Patterns
    )
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return ""
    }
    $matches = @()
    foreach ($pattern in $Patterns) {
        $matches += Get-ChildItem -LiteralPath $Directory -File -Filter $pattern -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    $matches = @($matches | Select-Object -Unique)
    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    return ""
}

function Get-BuildTargetNames {
    param([string[]]$Hints)

    $names = @("All_SNPs.vcf.gz", "common_all.vcf.gz")
    foreach ($hint in $Hints) {
        if (-not $hint) {
            continue
        }
        $lowerHint = "$hint".ToLowerInvariant()
        if ($lowerHint -match "hg38|grch38|hs38") {
            $names += @(
                "snps_hg38.vcf.gz",
                "All_SNPs_hg38_ref.tab.gz",
                "All_SNPs_HG38_ref.tab.gz",
                "All_SNPs_GRCh38_ref.tab.gz",
                "All_SNPs_grch38_ref.tab.gz",
                "snps_grch38.vcf.gz"
            )
        }
        if ($lowerHint -match "hg19|hg37|grch37|hs37") {
            $names += @(
                "snps_hg19.vcf.gz",
                "All_SNPs_hg19_ref.tab.gz",
                "All_SNPs_HG19_ref.tab.gz",
                "All_SNPs_GRCh37_ref.tab.gz",
                "All_SNPs_grch37_ref.tab.gz",
                "snps_grch37.vcf.gz"
            )
        }
    }
    return @($names | Select-Object -Unique)
}

function Get-ReferenceTargetDirectories {
    param([string]$Reference)
    if (-not $Reference) {
        return @()
    }
    $root = $Reference
    if (Test-Path -LiteralPath $root -PathType Leaf) {
        $root = Split-Path -Parent $root
    }
    return @(
        $root,
        (Join-Path $root "ref"),
        (Join-Path $root "microarray"),
        (Join-Path $root "genomes\microarray")
    )
}

function Get-ReferenceFastaCandidates {
    param([string]$Directory)
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(fa|fasta|fna)(\.gz)?$' } |
            Select-Object -ExpandProperty FullName
    )
}

function Select-ReferenceFasta {
    param([string[]]$Candidates, [string[]]$Hints)
    if ($Candidates.Count -eq 0) {
        return ""
    }
    foreach ($hint in $Hints) {
        if (-not $hint) {
            continue
        }
        $lowerHint = "$hint".ToLowerInvariant()
        $patterns = @()
        if ($lowerHint -match "hg19|hg37|grch37|hs37") {
            $patterns += @("hg19", "hg37", "grch37", "hs37")
        }
        if ($lowerHint -match "hg38|grch38|hs38") {
            $patterns += @("hg38", "grch38", "hs38")
        }
        foreach ($pattern in ($patterns | Select-Object -Unique)) {
            foreach ($candidate in $Candidates) {
                if ([System.IO.Path]::GetFileName($candidate).ToLowerInvariant().Contains($pattern)) {
                    return $candidate
                }
            }
        }
    }
    if ($Candidates.Count -eq 1) {
        return $Candidates[0]
    }
    return ""
}

function Resolve-InputReferenceFasta {
    param([string]$InputPath)
    if (-not $InputPath) {
        return ""
    }
    $directory = Split-Path -Parent $InputPath
    if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
        return ""
    }
    $manifestPath = Join-Path $directory "manifest.json"
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $refProperty = $manifest.files.PSObject.Properties["ref"]
            if ($refProperty -and $refProperty.Value) {
                $candidate = Join-Path $directory $refProperty.Value
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        } catch {
            Write-Warning "Unable to parse test genome manifest ${manifestPath}: $($_.Exception.Message)"
        }
    }
    return Select-ReferenceFasta -Candidates (Get-ReferenceFastaCandidates -Directory $directory) -Hints @($InputPath)
}

function Resolve-ReferenceFasta {
    param([string]$Reference, [string]$InputPath)

    if ($Reference -and (Test-Path -LiteralPath $Reference -PathType Leaf) -and $Reference -match '\.(fa|fasta|fna)(\.gz)?$') {
        return $Reference
    }

    $referenceCandidates = @()
    if ($Reference -and (Test-Path -LiteralPath $Reference -PathType Container)) {
        $referenceCandidates += Get-ReferenceFastaCandidates -Directory $Reference
        $referenceCandidates += Get-ReferenceFastaCandidates -Directory (Join-Path $Reference "genomes")
    }
    $referenceFasta = Select-ReferenceFasta -Candidates $referenceCandidates -Hints @($InputPath, $Reference)
    if ($referenceFasta) {
        return $referenceFasta
    }

    $inputFasta = Resolve-InputReferenceFasta -InputPath $InputPath
    if ($inputFasta) {
        return $inputFasta
    }

    return $Reference
}

function Resolve-ReferenceTargetTab {
    param([string[]]$References, [string[]]$Hints)

    $directories = @()
    foreach ($reference in $References) {
        $directories += Get-ReferenceTargetDirectories -Reference $reference
    }
    $directories = @($directories | Where-Object { $_ } | Select-Object -Unique)

    foreach ($targetName in (Get-BuildTargetNames -Hints $Hints)) {
        foreach ($directory in $directories) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                continue
            }
            $candidate = Join-Path $directory $targetName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    $patterns = @("All_SNPs*.tab.gz", "All_SNPs*.vcf.gz", "snps_*.vcf.gz", "common_all.vcf.gz")
    foreach ($directory in $directories) {
        $match = Get-SingleMatchingFile -Directory $directory -Patterns $patterns
        if ($match) {
            return $match
        }
    }
    return ""
}

function Resolve-InputTargetTab {
    param([string]$InputPath)
    if (-not $InputPath) {
        return ""
    }
    $directory = Split-Path -Parent $InputPath
    if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
        return ""
    }
    $stem = Get-InputStem -Path $InputPath
    $exact = Get-FirstExistingFile -Candidates @(
        (Join-Path $directory "$stem.targets.tab.gz"),
        (Join-Path $directory "$stem.target.tab.gz"),
        (Join-Path $directory "$stem.snps.tab.gz")
    )
    if ($exact) {
        return $exact
    }
    return Get-SingleMatchingFile -Directory $directory -Patterns @(
        "*.targets.tab.gz",
        "*.target.tab.gz",
        "*.snps.tab.gz",
        "All_SNPs*.tab.gz",
        "All_SNPs*.vcf.gz",
        "snps_*.vcf.gz",
        "common_all.vcf.gz"
    )
}

$inputPath = Get-ArgumentValue -Name "--input" -Arguments $forwardArgs
$refPath = Get-ArgumentValue -Name "--ref" -Arguments $forwardArgs
$originalRefPath = $refPath
$resolvedRefPath = Resolve-ReferenceFasta -Reference $refPath -InputPath $inputPath
if ($resolvedRefPath -and $resolvedRefPath -ne $refPath) {
    $forwardArgs = Set-ArgumentValue -Arguments $forwardArgs -Name "--ref" -Value $resolvedRefPath
    $refPath = $resolvedRefPath
}

if (-not (Has-Argument -Name "--ref-vcf-tab" -Arguments $forwardArgs)) {
    $targetTab = Resolve-InputTargetTab -InputPath $inputPath
    if (-not $targetTab) {
        $targetTab = Resolve-ReferenceTargetTab -References @($refPath, $originalRefPath) -Hints @($refPath, $originalRefPath, $inputPath)
    }
    if ($targetTab) {
        $forwardArgs += @("--ref-vcf-tab", $targetTab)
    }
}

& (Join-Path $scriptDir "run-wgsextract-env.ps1") wgsextract microarray @forwardArgs
exit $LASTEXITCODE
