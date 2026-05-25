$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$referenceLibrary = if ($env:WGSEXTRACT_REFERENCE_LIBRARY) { $env:WGSEXTRACT_REFERENCE_LIBRARY } else { Join-Path $bundleRoot "reference" }
$bootstrapArgs = @("ref", "bootstrap", "--ref", $referenceLibrary)

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -Algorithm SHA256 -LiteralPath $LiteralPath).Hash.ToLowerInvariant()
    }

    $stream = [System.IO.File]::OpenRead($LiteralPath)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha256.ComputeHash($stream)) -replace "-", "").ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Install-MappabilityMaps {
    $archiveUrl = if ($env:WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_URL) {
        $env:WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_URL
    } else {
        "https://github.com/theontho/wgsextract-cli/releases/download/v0.1.0/wgsextract-delly-mappability-maps.zip"
    }
    $expectedSha = if ($env:WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_SHA256) {
        $env:WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_SHA256
    } else {
        "cab55d8fe28f3c0da90cfdd0a8a4951dc5a33d182bbce3ef34392762eafe5d1b"
    }
    $archiveOverride = $env:WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE
    $mapFiles = @(
        "hg19.map.gz",
        "hg19.map.gz.fai",
        "hg19.map.gz.gzi",
        "hg38.map.gz",
        "hg38.map.gz.fai",
        "hg38.map.gz.gzi"
    )
    $mapsDir = Join-Path $referenceLibrary "maps"
    New-Item -ItemType Directory -Force -Path $mapsDir | Out-Null
    $missing = @($mapFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $mapsDir $_) -PathType Leaf) })
    if ($missing.Count -eq 0) {
        Write-Output "Delly mappability maps are already installed."
        return
    }

    if ($archiveOverride) {
        Write-Output "Using Delly mappability map archive: $archiveOverride"
        $archivePath = $archiveOverride
    } else {
        $archivePath = Join-Path $referenceLibrary "wgsextract-delly-mappability-maps.zip"
        Write-Output "Downloading Delly mappability maps from $archiveUrl..."
        if ($archiveUrl -match '^https?://') {
            Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath
        } else {
            Copy-Item -LiteralPath $archiveUrl -Destination $archivePath -Force
        }
    }

    try {
        if ($expectedSha) {
            $actualSha = Get-Sha256Hex -LiteralPath $archivePath
            if ($actualSha -ne $expectedSha.ToLowerInvariant()) {
                throw "Mappability map archive SHA256 mismatch: expected $expectedSha, got $actualSha"
            }
            Write-Output "Verified GitHub release asset SHA256: $actualSha"
        }

        Write-Output "Extracting Delly mappability maps to $mapsDir..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            foreach ($fileName in $mapFiles) {
                $expectedMember = "maps/$fileName"
                $entry = $archive.Entries | Where-Object {
                    $_.FullName.Replace('\', '/') -eq $expectedMember
                } | Select-Object -First 1
                if ($null -eq $entry) {
                    throw "Mappability map archive is missing $expectedMember."
                }
                $target = Join-Path $mapsDir $fileName
                $source = $entry.Open()
                try {
                    $destination = [System.IO.File]::Open($target, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                    try {
                        $source.CopyTo($destination)
                    } finally {
                        $destination.Dispose()
                    }
                } finally {
                    $source.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
        Write-Output "Delly mappability maps are installed."
    } finally {
        if (-not $archiveOverride -and (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            Remove-Item -LiteralPath $archivePath -Force
        }
    }
}

& (Join-Path $scriptDir "run-wgsextract.ps1") @bootstrapArgs
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    exit $exitCode
}

if ($env:WGSEXTRACT_SKIP_MAPPABILITY_MAPS -ne "1") {
    Install-MappabilityMaps
}
