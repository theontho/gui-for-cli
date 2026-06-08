$ErrorActionPreference = "Stop"

if ($args.Count -lt 1) {
    Write-Error "Usage: run-wgsextract-env.ps1 COMMAND [ARG...]"
    exit 64
}

$scriptDir = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $scriptDir
$bundleRoot = Split-Path -Parent $scriptsRoot
$appDir = if ($env:WGSEXTRACT_APP_DIR) { $env:WGSEXTRACT_APP_DIR } else { Join-Path $bundleRoot "runtime\wgsextract-cli\app" }
$runtimePixi = Join-Path $bundleRoot "runtime\wgsextract-cli\.pixi\bin\pixi.exe"

function Get-PacmanBinDirectories {
    $directories = @()
    foreach ($configured in @($env:WGSEXTRACT_PACMAN_UCRT64_BIN, $env:UCRT64_BIN)) {
        if ($configured) {
            $directories += $configured
        }
    }
    if ($env:MSYS2_ROOT) {
        $directories += (Join-Path $env:MSYS2_ROOT "ucrt64\bin")
    }
    $directories += "C:\msys64\ucrt64\bin"
    if ($env:LOCALAPPDATA) {
        $directories += (Join-Path $env:LOCALAPPDATA "Programs\msys64\ucrt64\bin")
    }

    $result = @()
    foreach ($directory in $directories) {
        if (-not $directory) {
            continue
        }
        $result += $directory
        $parent = Split-Path -Parent $directory
        if ($parent -and (Split-Path -Leaf $parent).ToLowerInvariant() -eq "ucrt64") {
            $result += (Join-Path (Split-Path -Parent $parent) "usr\bin")
        }
    }
    return $result | Select-Object -Unique
}

function Resolve-NativeCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([System.IO.Path]::IsPathRooted($Name)) {
        if (Test-Path -LiteralPath $Name -PathType Leaf) {
            return $Name
        }
        if (-not [System.IO.Path]::HasExtension($Name)) {
            $withExe = "$Name.exe"
            if (Test-Path -LiteralPath $withExe -PathType Leaf) {
                return $withExe
            }
        }
        return $null
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command -and $command.CommandType -in @("Application", "ExternalScript")) {
        if ($command.Path) {
            return $command.Path
        }
        if ($command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
            return $command.Source
        }
    }

    $names = @($Name)
    if (-not [System.IO.Path]::HasExtension($Name)) {
        $names += "$Name.exe"
    }
    foreach ($directory in Get-PacmanBinDirectories) {
        foreach ($candidateName in $names) {
            $candidate = Join-Path $directory $candidateName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
    return $null
}

function Invoke-ForwardedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [object[]]$InputObjects = @()
    )

    if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
        $InputObjects | & $FilePath @Arguments
    } else {
        & $FilePath @Arguments
    }
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $appDir -PathType Container)) {
    if ($env:WGSEXTRACT_ALLOW_PATH_FALLBACK -eq "1") {
        $candidate = Get-Command $args[0] -ErrorAction SilentlyContinue
        if ($candidate) {
            if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
                Invoke-ForwardedCommand -FilePath $args[0] -Arguments @($args | Select-Object -Skip 1) -InputObjects @($input)
            } else {
                Invoke-ForwardedCommand -FilePath $args[0] -Arguments @($args | Select-Object -Skip 1)
            }
        }
    }
    Write-Error "WGS Extract bundle runtime is not installed at $appDir. Run setup before running commands."
    exit 127
}

$commandName = [string]$args[0]
if ($commandName -ne "wgsextract") {
    $nativeCommand = Resolve-NativeCommand -Name $commandName
    if ($nativeCommand) {
        if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
            Invoke-ForwardedCommand -FilePath $nativeCommand -Arguments @($args | Select-Object -Skip 1) -InputObjects @($input)
        } else {
            Invoke-ForwardedCommand -FilePath $nativeCommand -Arguments @($args | Select-Object -Skip 1)
        }
    }
}

$pixi = $env:PIXI
if ($pixi -and -not (Test-Path -LiteralPath $pixi -PathType Leaf)) {
    Write-Error "PIXI is set but is not executable: $pixi"
    exit 127
}
if (-not $pixi) {
    $command = Get-Command pixi -ErrorAction SilentlyContinue
    if ($command -and $command.CommandType -in @("Application", "ExternalScript")) {
        if ($command.Path) {
            $pixi = $command.Path
        } elseif ($command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
            $pixi = $command.Source
        }
    } elseif (Test-Path -LiteralPath $runtimePixi -PathType Leaf) {
        $pixi = $runtimePixi
    } else {
        $homePixi = Join-Path $HOME ".pixi\bin\pixi.exe"
        if (Test-Path -LiteralPath $homePixi -PathType Leaf) {
            $pixi = $homePixi
        }
    }
}
if (-not $pixi) {
    Write-Error "Pixi was not found. Run setup again or install Pixi first."
    exit 127
}

Push-Location $appDir
try {
    if ($env:WGSEXTRACT_FORWARD_STDIN -eq "1") {
        Invoke-ForwardedCommand -FilePath $pixi -Arguments (@("run") + $args) -InputObjects @($input)
    } else {
        Invoke-ForwardedCommand -FilePath $pixi -Arguments (@("run") + $args)
    }
} finally {
    Pop-Location
}
