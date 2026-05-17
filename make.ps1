param(
    [Parameter(Position = 0)]
    [string]$Action = "help",

    [string]$Platform = "",
    [string]$Suite = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RunnerArgs = @()
)

$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
Set-Location $PSScriptRoot

$Script:PrecheckFailures = 0
$Script:NodeVersion = "24.15.0"

function Show-Help {
    @"
Usage:
  .\make.ps1 setup
  .\make.ps1 precheck
  .\make.ps1 env

Actions:
  setup      Install and prepare the Windows development environment.
  precheck   Verify required development tools and repository setup.
  env        Print the direct platform runner commands to use after setup.
  help       Show this help.

This script only prepares the Windows dev environment. After setup passes,
run platform tasks directly with Python:

  python tools\platform.py list
  python tools\platform.py test windows
  python tools\platform.py build windows
  python tools\platform.py package windows
"@
}

function Show-PlatformRunnerHint {
    param(
        [string]$RequestedAction,
        [switch]$SkipSetupSteps
    )

    Write-Host "make.ps1 no longer wraps tools\platform.py subcommands."
    Write-Host ""
    if (-not $SkipSetupSteps) {
        Write-Host "First prepare this machine:"
        Write-Host "  .\make.ps1 setup"
        Write-Host "  .\make.ps1 precheck"
        Write-Host ""
    }
    Write-Host "Then run the platform runner directly:"
    $python = Resolve-Python -Quiet
    $pythonCommand = if ($python) { $python } else { "python" }
    $pythonDisplay = if ($pythonCommand -match '\s') { "`"$pythonCommand`"" } else { $pythonCommand }
    if (-not [string]::IsNullOrWhiteSpace($RequestedAction)) {
        $items = @()
        if (-not [string]::IsNullOrWhiteSpace($Platform)) {
            $items += $Platform
        }
        if (-not [string]::IsNullOrWhiteSpace($Suite)) {
            $items += $Suite
        }
        $items += $RunnerArgs
        $suffix = ($items -join " ").Trim()
        if ($suffix.Length -gt 0) {
            Write-Host "  $pythonDisplay tools\platform.py $RequestedAction $suffix"
        }
        else {
            Write-Host "  $pythonDisplay tools\platform.py $RequestedAction <target-or-suite>"
        }
    }
    else {
        Write-Host "  $pythonDisplay tools\platform.py list"
    }
}

function Test-PythonExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList @($Arguments + @("--version")) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        return $process.ExitCode -eq 0
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-Python {
    param([switch]$Quiet)

    foreach ($candidate in @("python3", "python")) {
        $python = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($python -and (Test-PythonExecutable $python.Source)) {
            return $python.Source
        }
    }

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pythonLauncher -and (Test-PythonExecutable $pythonLauncher.Source -Arguments @("-3"))) {
        return $pythonLauncher.Source
    }

    if ($Quiet) {
        return ""
    }
    throw "Python was not found on PATH. Install Python 3, then rerun .\make.ps1 setup."
}

function Add-DevToolPaths {
    $paths = @(
        (Join-Path $PSScriptRoot ".dotnet-sdk"),
        (Join-Path $env:USERPROFILE ".cargo\bin"),
        (Join-Path $env:ProgramFiles "Go\bin")
    )

    $nodeRoot = Join-Path $PSScriptRoot ".node"
    if (Test-Path $nodeRoot) {
        $nodeDirs = Get-ChildItem -LiteralPath $nodeRoot -Directory -Filter "node-v*-win-x64" -ErrorAction SilentlyContinue |
            Sort-Object { Get-NodeDirectoryVersion $_.Name }
        foreach ($nodeDir in $nodeDirs) {
            $paths += $nodeDir.FullName
        }
    }

    foreach ($path in $paths) {
        if ((Test-Path $path) -and -not (($env:PATH -split [System.IO.Path]::PathSeparator) -contains $path)) {
            $env:PATH = "$path$([System.IO.Path]::PathSeparator)$env:PATH"
        }
    }
}

function Get-NodeDirectoryVersion {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -match "^node-v(?<version>\d+(?:\.\d+){0,3})-win-x64$") {
        return [version]$Matches.version
    }
    return [version]"0.0.0"
}

function Resolve-DotNet {
    $localDotNet = Join-Path $PSScriptRoot ".dotnet-sdk\dotnet.exe"
    if (Test-Path $localDotNet) {
        return $localDotNet
    }
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnet) {
        return $dotnet.Source
    }
    return ""
}

function Test-DotNetSdk {
    $dotnet = Resolve-DotNet
    if ([string]::IsNullOrWhiteSpace($dotnet)) {
        return $false
    }
    $sdks = & $dotnet --list-sdks 2>$null
    return $LASTEXITCODE -eq 0 -and ($sdks | Where-Object { $_ -match "^10\." })
}

function Install-DotNetSdk {
    if (Test-DotNetSdk) {
        return
    }

    $installScript = Join-Path $PSScriptRoot "tmp\dotnet-install.ps1"
    New-Item -ItemType Directory -Force (Split-Path $installScript -Parent) | Out-Null
    if (-not (Test-Path $installScript)) {
        Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $installScript
    }

    $installDir = Join-Path $PSScriptRoot ".dotnet-sdk"
    & $installScript -Channel "10.0" -InstallDir $installDir -Architecture "x64" -NoPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install the .NET 10 SDK."
    }
}

function Install-WithWinget {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "$Name is missing and winget is not available to install it."
    }

    Write-Host "Installing $Name with winget..."
    & $winget.Source install --id $Id -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Name."
    }
}

function Get-NodeMajorVersion {
    Add-DevToolPaths
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        return 0
    }
    $version = (& $node.Source --version 2>$null).TrimStart("v")
    if ($version -match "^(\d+)") {
        return [int]$Matches[1]
    }
    return 0
}

function Install-NodeRuntime {
    if ((Get-NodeMajorVersion) -ge 22) {
        return
    }

    $nodeRoot = Join-Path $PSScriptRoot ".node"
    $nodeDirectoryName = "node-v$Script:NodeVersion-win-x64"
    $nodeDirectory = Join-Path $nodeRoot $nodeDirectoryName
    if (-not (Test-Path $nodeDirectory)) {
        New-Item -ItemType Directory -Force $nodeRoot | Out-Null
        $zipPath = Join-Path $PSScriptRoot "tmp\$nodeDirectoryName.zip"
        New-Item -ItemType Directory -Force (Split-Path $zipPath -Parent) | Out-Null
        $nodeUri = "https://nodejs.org/dist/v$Script:NodeVersion/$nodeDirectoryName.zip"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & $curl.Source --fail --location --output $zipPath $nodeUri
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to download Node.js $Script:NodeVersion."
            }
        }
        else {
            Invoke-WebRequest -Uri $nodeUri -OutFile $zipPath
        }
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($tar) {
            & $tar.Source -xf $zipPath -C $nodeRoot
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to extract Node.js $Script:NodeVersion."
            }
        }
        else {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $nodeRoot -Force
        }
    }

    Add-DevToolPaths
    if ((Get-NodeMajorVersion) -lt 22) {
        throw "Failed to install local Node.js $Script:NodeVersion."
    }
}

function Ensure-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$WingetId,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        return
    }
    Install-WithWinget -Id $WingetId -Name $Name
    Add-DevToolPaths
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $PSScriptRoot
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Install-WebUIDependencies {
    $npm = Get-Command npm -ErrorAction Stop
    Invoke-Checked -FilePath $npm.Source -Arguments @("install") -WorkingDirectory (Join-Path $PSScriptRoot "platform\typescript")
}

function Initialize-DevIdentityAndHooks {
    $python = Resolve-Python
    if (-not (Test-Path (Join-Path $PSScriptRoot ".dev_id"))) {
        Invoke-Checked -FilePath $python -Arguments @("scripts\dev-register.py")
    }
    Invoke-Checked -FilePath $python -Arguments @("scripts\setup-hooks.py")
}

function Invoke-Setup {
    Add-DevToolPaths

    if (-not (Resolve-Python -Quiet)) {
        Install-WithWinget -Id "Python.Python.3.12" -Name "Python 3"
    }

    Install-DotNetSdk

    Install-NodeRuntime

    Ensure-Command -Command "cargo" -WingetId "Rustlang.Rustup" -Name "Rustup"
    Ensure-Command -Command "go" -WingetId "GoLang.Go" -Name "Go"

    Install-WebUIDependencies
    Initialize-DevIdentityAndHooks

    Write-Host ""
    Write-Host "Windows dev environment is set up."
    Show-PlatformRunnerHint -RequestedAction "" -SkipSetupSteps
}

function Add-PrecheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [string]$Detail = ""
    )

    if ($Passed) {
        Write-Host "[ok]      $Name $Detail"
    }
    else {
        Write-Host "[missing] $Name $Detail"
        $Script:PrecheckFailures += 1
    }
}

function Invoke-Precheck {
    Add-DevToolPaths
    $Script:PrecheckFailures = 0

    $python = Resolve-Python -Quiet
    Add-PrecheckResult -Name "Python 3" -Passed (-not [string]::IsNullOrWhiteSpace($python)) -Detail $python

    Add-PrecheckResult -Name ".NET 10 SDK" -Passed (Test-DotNetSdk) -Detail (Resolve-DotNet)

    $nodeMajor = Get-NodeMajorVersion
    Add-PrecheckResult -Name "Node.js 22+" -Passed ($nodeMajor -ge 22) -Detail "major=$nodeMajor"

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    Add-PrecheckResult -Name "npm" -Passed ($null -ne $npm) -Detail $(if ($npm) { $npm.Source } else { "" })

    $tsc = Join-Path $PSScriptRoot "platform\typescript\node_modules\.bin\tsc.cmd"
    Add-PrecheckResult -Name "WebUI npm dependencies" -Passed (Test-Path $tsc) -Detail "platform\typescript\node_modules"

    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    Add-PrecheckResult -Name "Rust Cargo" -Passed ($null -ne $cargo) -Detail $(if ($cargo) { $cargo.Source } else { "" })

    $go = Get-Command go -ErrorAction SilentlyContinue
    Add-PrecheckResult -Name "Go" -Passed ($null -ne $go) -Detail $(if ($go) { $go.Source } else { "" })

    Add-PrecheckResult -Name "developer identity" -Passed (Test-Path (Join-Path $PSScriptRoot ".dev_id")) -Detail ".dev_id"

    if ($python) {
        & $python "scripts\setup-hooks.py" "--check"
        Add-PrecheckResult -Name "git hooks" -Passed ($LASTEXITCODE -eq 0)
    }
    else {
        Add-PrecheckResult -Name "git hooks" -Passed $false -Detail "Python is required to check hooks."
    }

    Write-Host ""
    if ($Script:PrecheckFailures -eq 0) {
        Write-Host "Precheck passed. Use tools\platform.py for build/test/package tasks:"
        Show-PlatformRunnerHint -RequestedAction "" -SkipSetupSteps
        return
    }

    Write-Host "Precheck failed with $Script:PrecheckFailures issue(s). Run .\make.ps1 setup, then rerun .\make.ps1 precheck."
    exit 1
}

function Show-Environment {
    Add-DevToolPaths
    $dotnet = Resolve-DotNet
    if (-not [string]::IsNullOrWhiteSpace($dotnet)) {
        Write-Host "DOTNET=$dotnet"
    }
    Write-Host "GOTOOLCHAIN=go1.25.0"
    Write-Host ""
    Show-PlatformRunnerHint -RequestedAction "" -SkipSetupSteps
}

switch ($Action) {
    "help" {
        Show-Help
    }
    "setup" {
        Invoke-Setup
    }
    "precheck" {
        Invoke-Precheck
    }
    "preheck" {
        Invoke-Precheck
    }
    "env" {
        Show-Environment
    }
    default {
        Show-PlatformRunnerHint -RequestedAction $Action
        exit 2
    }
}
