param(
    [Parameter(Position = 0)]
    [string]$Target = "help",

    [string]$DotNet = $(if ($env:DOTNET) { $env:DOTNET } else { "" }),
    [string]$Configuration = "Debug",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$BenchmarkExecutable = "",
    [int]$BenchmarkIterations = 7,
    [string]$Cert = $(if ($env:CERT) { $env:CERT } else { "" }),
    [string]$CertPassword = $(if ($env:CERT_PASSWORD) { $env:CERT_PASSWORD } else { "" }),
    [switch]$Live
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

# Keep Windows-specific targets in this PowerShell task runner; the POSIX Makefile is for Unix-like shells.
if ([string]::IsNullOrWhiteSpace($DotNet)) {
    $localDotNet = Join-Path $PSScriptRoot ".dotnet-sdk\dotnet.exe"
    $DotNet = if (Test-Path $localDotNet) { $localDotNet } else { "dotnet" }
}

$targets = [ordered]@{
    "help" = "Show available Windows task targets."
    "test-webui" = "Build and run the Web UI TypeScript tests."
    "test-core" = "Run C# core parity tests."
    "build-core" = "Build the C# core library."
    "build" = "Build all .NET projects as x64."
    "app" = "Build and launch the native app."
    "ax-smoke" = "Run a static UI Automation smoke check, or pass -Live for a running app."
    "publish" = "Publish the native app into out\\windows-publish. Local/manual only."
    "publish-readytorun" = "Publish the native app with ReadyToRun into out\\windows-publish-readytorun."
    "publish-nativeaot" = "Publish the native app with NativeAOT into out\\windows-publish-nativeaot."
    "benchmark-windows-app" = "Measure native Windows app startup, idle memory, and publish size."
    "package-msix" = "Build an MSIX package. Set -Cert and -CertPassword for signed packages."
    "package-bootstrap" = "Build a framework-dependent app payload ZIP for runtime-downloading installers."
    "package-webui" = "Build a portable WebUI package with node.exe, assets, built-in strings, and the default bundle."
    "package-electron" = "Build a packaged Electron WebUI app for benchmark and packaging comparisons."
}

function Invoke-CommandChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Stop-WindowsAppInstances {
    $processes = Get-Process -Name "GUIForCLIWindows" -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        Stop-Process -Id $process.Id -Force
    }
}

function Resolve-WindowsPlatform {
    param([string]$RuntimeIdentifier)

    switch ($RuntimeIdentifier) {
        "win-x86" { "x86" }
        "win-x64" { "x64" }
        "win-arm64" { "ARM64" }
        default { throw "Unsupported RuntimeIdentifier '$RuntimeIdentifier'. Expected win-x86, win-x64, or win-arm64." }
    }
}

function Invoke-WindowsPublish {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [switch]$ReadyToRun,
        [switch]$NativeAot
    )

    $platform = Resolve-WindowsPlatform -RuntimeIdentifier $RuntimeIdentifier
    $arguments = @(
        "publish",
        "Apps\Windows\GUIForCLIWindows\GUIForCLIWindows.csproj",
        "-c", "Release",
        "-o", $OutputDirectory,
        "-p:Platform=$platform",
        "-p:RuntimeIdentifier=$RuntimeIdentifier",
        "-p:WindowsAppSDKSelfContained=true",
        "-p:SelfContained=true"
    )
    if ($ReadyToRun) {
        $arguments += "-p:PublishReadyToRun=true"
    }
    if ($NativeAot) {
        $arguments += @("-p:PublishAot=true", "-p:PublishTrimmed=true")
    }
    $arguments += "/nr:false"

    Invoke-CommandChecked -FilePath $DotNet -Arguments $arguments
}

function Show-Help {
    "Available Windows targets:"
    foreach ($entry in $targets.GetEnumerator()) {
        "  {0,-22} {1}" -f $entry.Key, $entry.Value
    }
}

switch ($Target) {
    "help" {
        Show-Help
    }
    "test-webui" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "test")
    }
    "test-core" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("run", "--project", "Tests\GUIForCLIWindows.CoreTests\GUIForCLIWindows.CoreTests.csproj")
    }
    "build-core" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "Sources\GUIForCLIWindows.Core\GUIForCLIWindows.Core.csproj")
    }
    "build" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "GUIForCLIWindows.sln", "-p:Platform=x64")
    }
    "app" {
        Stop-WindowsAppInstances
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "GUIForCLIWindows.sln", "-p:Platform=x64")
        $exe = Resolve-Path Apps\Windows\GUIForCLIWindows\bin\x64\$Configuration\net10.0-windows10.0.19041.0\win-x64\GUIForCLIWindows.exe
        Start-Process -FilePath $exe
    }
    "ax-smoke" {
        $smokeArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\windows-ax-smoke.ps1")
        if (-not $Live) {
            $smokeArgs += "-StaticOnly"
        }
        Invoke-CommandChecked -FilePath pwsh -Arguments $smokeArgs
    }
    "publish" {
        Invoke-WindowsPublish -OutputDirectory "out\windows-publish"
    }
    "publish-readytorun" {
        Invoke-WindowsPublish -OutputDirectory "out\windows-publish-readytorun" -ReadyToRun
    }
    "publish-nativeaot" {
        Invoke-WindowsPublish -OutputDirectory "out\windows-publish-nativeaot" -NativeAot
    }
    "benchmark-windows-app" {
        $exe = if ([string]::IsNullOrWhiteSpace($BenchmarkExecutable)) {
            "out\windows-publish\GUIForCLIWindows.exe"
        } else {
            $BenchmarkExecutable
        }
        Invoke-CommandChecked -FilePath pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\benchmark-windows-app.ps1", "-Executable", $exe, "-Iterations", "$BenchmarkIterations")
    }
    "package-msix" {
        $packageArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\package-windows-msix.ps1", "-DotNet", $DotNet)
        if ($Cert) {
            $packageArgs += @("-CertificatePath", $Cert, "-CertificatePassword", $CertPassword)
        }
        Invoke-CommandChecked -FilePath pwsh -Arguments $packageArgs
    }
    "package-bootstrap" {
        Invoke-CommandChecked -FilePath pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\package-windows-bootstrap.ps1", "-DotNet", $DotNet)
    }
    "package-webui" {
        Invoke-CommandChecked -FilePath pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\package-windows-webui.ps1")
    }
    "package-electron" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "electron:package", "--", "--out", "out\windows-electron", "--platform", "win32", "--arch", "x64")
    }
    default {
        Write-Error "Unknown target '$Target'. Run '.\make.ps1 help' for available targets."
        exit 2
    }
}
