$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$runtime = Join-Path $scriptDir "run-wgsextract-env.ps1"

function Get-IndexInputMessage {
    param([Parameter(Mandatory = $true)][string]$Value)

    $lower = $Value.ToLowerInvariant()
    if ($lower.EndsWith(".crai")) {
        $dataPath = $Value.Substring(0, $Value.Length - 5)
        return "Selected CRAM index file: $Value`nChoose the CRAM data file instead: $dataPath"
    }
    if ($lower.EndsWith(".bam.bai")) {
        $dataPath = $Value.Substring(0, $Value.Length - 4)
        return "Selected BAM index file: $Value`nChoose the BAM data file instead: $dataPath"
    }
    if ($lower.EndsWith(".bai")) {
        return "Selected BAM index file: $Value`nChoose the BAM data file, not its .bai index."
    }
    return $null
}

for ($index = 0; $index -lt $args.Count; $index += 1) {
    $argument = [string]$args[$index]
    $inputPath = $null
    if ($argument -eq "--input" -and $index + 1 -lt $args.Count) {
        $inputPath = [string]$args[$index + 1]
    } elseif ($argument.StartsWith("--input=")) {
        $inputPath = $argument.Substring("--input=".Length)
    }

    if ($null -ne $inputPath) {
        $message = Get-IndexInputMessage -Value $inputPath
        if ($message) {
            [Console]::Error.WriteLine($message)
            exit 1
        }
    }
}

if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
    $input | & $runtime wgsextract @args
} else {
    & $runtime wgsextract @args
}
exit $LASTEXITCODE
