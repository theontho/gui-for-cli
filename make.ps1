param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "platforms", "setup", "lint", "format", "build", "run", "test", "clean", "benchmark", "screenshot", "package", "release-build", "ci", "ci-fast")]
    [string]$Action = "help",

    [string]$Platform = "",
    [string]$Suite = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RunnerArgs = @(),

    [string]$DotNet = $(if ($env:DOTNET) { $env:DOTNET } else { "" }),
    [string]$Configuration = $(if ($env:CONFIGURATION) { $env:CONFIGURATION } else { "Debug" }),
    [string]$RuntimeIdentifier = $(if ($env:RUNTIME_IDENTIFIER) { $env:RUNTIME_IDENTIFIER } else { "win-x64" }),
    [string]$BenchmarkExecutable = $(if ($env:BENCHMARK_EXECUTABLE) { $env:BENCHMARK_EXECUTABLE } else { "" }),
    [int]$BenchmarkIterations = $(if ($env:BENCHMARK_ITERATIONS) { [int]$env:BENCHMARK_ITERATIONS } else { 7 }),
    [string]$Cert = $(if ($env:CERT) { $env:CERT } else { "" }),
    [string]$CertPassword = $(if ($env:CERT_PASSWORD) { $env:CERT_PASSWORD } else { "" }),
    [switch]$Live,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Resolve-Python {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }
    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pythonLauncher) {
        return $pythonLauncher.Source
    }
    throw "Python was not found on PATH."
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Set-RunnerEnvironment {
    if ([string]::IsNullOrWhiteSpace($DotNet)) {
        $localDotNet = Join-Path $PSScriptRoot ".dotnet-sdk\dotnet.exe"
        $DotNet = if (Test-Path $localDotNet) { $localDotNet } else { "dotnet" }
    }
    if (-not [string]::IsNullOrWhiteSpace($DotNet)) {
        $env:DOTNET = $DotNet
    }
    $env:CONFIGURATION = $Configuration
    $env:RUNTIME_IDENTIFIER = $RuntimeIdentifier
    $env:BENCHMARK_EXECUTABLE = $BenchmarkExecutable
    $env:BENCHMARK_ITERATIONS = "$BenchmarkIterations"
    $env:CERT = $Cert
    $env:CERT_PASSWORD = $CertPassword
    if ($Live) {
        $env:LIVE = "1"
    }
    else {
        Remove-Item Env:LIVE -ErrorAction SilentlyContinue
    }
}

function Show-Help {
    @"
Usage:
  .\make.ps1 <action> -Platform <name>
  .\make.ps1 <action> -Suite <name>
  .\make.ps1 benchmark <suite-or-command> [benchmark args]
  .\make.ps1 screenshot <suite-or-surface> [screenshot args]

Actions:
  setup lint format build run test clean benchmark screenshot package release-build

Examples:
  .\make.ps1 build -Platform windows
  .\make.ps1 run -Platform webui
  .\make.ps1 test -Suite stable
  .\make.ps1 package -Platform webui
  .\make.ps1 release-build -Suite stable

Run '.\make.ps1 platforms' for available platform names and suites.
"@
}

function Invoke-PlatformRunner {
    param([string]$RunnerAction)

    Set-RunnerEnvironment
    $python = Resolve-Python
    $arguments = @("tools/platform.py")
    if ($DryRun) {
        $arguments += "--dry-run"
    }
    $arguments += $RunnerAction
    if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        $arguments += $Platform
    }
    if (-not [string]::IsNullOrWhiteSpace($Suite)) {
        $arguments += "suite:$Suite"
    }
    $arguments += $RunnerArgs
    Invoke-Checked -FilePath $python -Arguments $arguments
}

switch ($Action) {
    "help" {
        Show-Help
    }
    "platforms" {
        $python = Resolve-Python
        Invoke-Checked -FilePath $python -Arguments @("tools/platform.py", "list")
    }
    "ci" {
        $python = Resolve-Python
        Invoke-Checked -FilePath $python -Arguments @("tools/ci/ci_local.py")
    }
    "ci-fast" {
        $python = Resolve-Python
        Invoke-Checked -FilePath $python -Arguments @("tools/ci/ci_local.py", "--fast")
    }
    default {
        Invoke-PlatformRunner -RunnerAction $Action
    }
}
