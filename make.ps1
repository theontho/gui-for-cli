param(
    [Parameter(Position = 0)]
    [string]$Action = "help",

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
  .\make.ps1 <target> [NAME=value ...]

Environment:
  setup              Install Python, Node.js, and Rust if missing, npm dependencies, dev identity, and git hooks.
  precheck           Verify required development tools and repository setup.
  worktree-setup     Create and initialize a developer Git worktree (BRANCH=name).
  worktree-teardown  Remove a registered developer Git worktree (BRANCH=name).

Tasks (same as the Makefile, via tools\tasks.py):
  run                Build and serve the Web UI in a browser (BUNDLE=path PORT=port).
  dev                Serve the Web UI with watch and reload.
  tauri              Run the Tauri desktop app in dev mode.
  build              Compile the TypeScript Web UI.
  build-tauri        Build the Tauri desktop app.
  lint               Typecheck, validate bundles, lint locales, compile Python tooling, check duplication.
  test               Run TypeScript and Python tooling tests.
  ci                 Run lint and tests.
  package            Build the Tauri NSIS installer into out\release\tauri.
  clean              Remove build outputs.
"@
}

$Script:TaskTargets = @{
    "run"         = @("run", "web")
    "dev"         = @("run", "dev")
    "tauri"       = @("run", "tauri")
    "build"       = @("build", "web")
    "build-tauri" = @("build", "tauri")
    "lint"        = @("lint")
    "test"        = @("test")
    "ci"          = @("ci")
    "package"     = @("package", "tauri")
    "clean"       = @("clean")
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
        (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".cargo\bin")
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
    Invoke-Checked -FilePath $npm.Source -Arguments @("install") -WorkingDirectory (Join-Path $PSScriptRoot "app")
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

    Install-NodeRuntime

    Ensure-Command -Command "cargo" -WingetId "Rustlang.Rustup" -Name "Rustup"

    Install-WebUIDependencies
    Initialize-DevIdentityAndHooks

    Write-Host ""
    Write-Host "Windows dev environment is set up. Run .\make.ps1 help for tasks."
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

    $nodeMajor = Get-NodeMajorVersion
    Add-PrecheckResult -Name "Node.js 22+" -Passed ($nodeMajor -ge 22) -Detail "major=$nodeMajor"

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    Add-PrecheckResult -Name "npm" -Passed ($null -ne $npm) -Detail $(if ($npm) { $npm.Source } else { "" })

    $tsc = Join-Path $PSScriptRoot "app\node_modules\.bin\tsc.cmd"
    Add-PrecheckResult -Name "WebUI npm dependencies" -Passed (Test-Path $tsc) -Detail "app\node_modules"

    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    Add-PrecheckResult -Name "Rust Cargo" -Passed ($null -ne $cargo) -Detail $(if ($cargo) { $cargo.Source } else { "" })

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
        Write-Host "Precheck passed. Run .\make.ps1 help for tasks."
        return
    }

    Write-Host "Precheck failed with $Script:PrecheckFailures issue(s). Run .\make.ps1 setup, then rerun .\make.ps1 precheck."
    exit 1
}

function Invoke-PythonTool {
    param([Parameter(Mandatory = $true)][string[]]$ToolArguments)

    Add-DevToolPaths
    $python = Resolve-Python -Quiet
    $prefix = @()
    if ([string]::IsNullOrWhiteSpace($python)) {
        $uv = Get-Command uv -ErrorAction SilentlyContinue
        if (-not $uv) {
            throw "Python was not found on PATH. Install Python 3 or uv, then rerun .\make.ps1 $Action."
        }
        $python = $uv.Source
        $prefix = @("run", "python")
    }

    $arguments = @($prefix + $ToolArguments)
    foreach ($item in $RunnerArgs) {
        if ($item -match "^(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$") {
            Set-Item -Path "Env:\$($Matches.name)" -Value $Matches.value
        }
        else {
            $arguments += $item
        }
    }

    Invoke-Checked -FilePath $python -Arguments $arguments
}

switch ($Action) {
    "help" {
        Show-Help
    }
    "setup" {
        Invoke-Setup
    }
    "worktree-setup" {
        Invoke-PythonTool -ToolArguments @("tools/worktree.py", "setup")
    }
    "worktree-teardown" {
        Invoke-PythonTool -ToolArguments @("tools/worktree.py", "teardown")
    }
    "precheck" {
        Invoke-Precheck
    }
    default {
        if (-not $Script:TaskTargets.ContainsKey($Action)) {
            Write-Host "Unknown target: $Action"
            Write-Host ""
            Show-Help
            exit 2
        }
        Invoke-PythonTool -ToolArguments (@("tools/tasks.py") + $Script:TaskTargets[$Action])
    }
}
