param(
    [Parameter(Position = 0)]
    [string]$Target = "help",

    [string]$DotNet = $(if ($env:DOTNET) { $env:DOTNET } else { "" }),
    [string]$Configuration = "Debug",
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
    "package-msix" = "Build an MSIX package. Set -Cert and -CertPassword for signed packages."
    "package-bootstrap" = "Build a framework-dependent app payload ZIP for runtime-downloading installers."
    "package-webui" = "Build a portable WebUI package with node.exe, assets, built-in strings, and the default bundle."
    "package-electron" = "Build a packaged Electron WebUI app for benchmark and packaging comparisons."
    "nodegui" = "Build and launch the NodeGui/Qt WebUI shell."
    "nodegui-smoke" = "Load the NodeGui shared model without opening a window."
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
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("publish", "Apps\Windows\GUIForCLIWindows\GUIForCLIWindows.csproj", "-c", "Release", "-o", "out\windows-publish", "-p:Platform=x64", "-p:WindowsAppSDKSelfContained=true", "-p:SelfContained=true")
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
    "nodegui" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "nodegui", "--", "--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    "nodegui-smoke" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "nodegui:smoke", "--", "--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    default {
        Write-Error "Unknown target '$Target'. Run '.\make.ps1 help' for available targets."
        exit 2
    }
}
