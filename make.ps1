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

if ([string]::IsNullOrWhiteSpace($DotNet)) {
    $localDotNet = Join-Path $PSScriptRoot ".dotnet-sdk\dotnet.exe"
    $DotNet = if (Test-Path $localDotNet) { $localDotNet } else { "dotnet" }
}

$targets = [ordered]@{
    "help" = "Show available Windows task targets."
    "test-webui" = "Build and run the Web UI TypeScript tests."
    "test-windows-core" = "Run Windows C# core parity tests."
    "build-windows-core" = "Build the Windows C# core library."
    "build-windows" = "Build all Windows .NET projects as x64."
    "run-windows" = "Build and launch the native Windows app."
    "ax-smoke-windows" = "Run a static Windows UI Automation smoke check, or pass -Live for a running app."
    "publish-windows" = "Publish the native Windows app into out\\windows-publish. Local/manual only."
    "package-windows-msix" = "Build an MSIX package. Set -Cert and -CertPassword for signed packages."
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
    "test-windows-core" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("run", "--project", "Tests\GUIForCLIWindows.CoreTests\GUIForCLIWindows.CoreTests.csproj")
    }
    "build-windows-core" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "Sources\GUIForCLIWindows.Core\GUIForCLIWindows.Core.csproj")
    }
    "build-windows" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "GUIForCLIWindows.sln", "-p:Platform=x64")
    }
    "run-windows" {
        Stop-WindowsAppInstances
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("build", "GUIForCLIWindows.sln", "-p:Platform=x64")
        $exe = Resolve-Path Apps\Windows\GUIForCLIWindows\bin\x64\$Configuration\net10.0-windows10.0.19041.0\win-x64\GUIForCLIWindows.exe
        Start-Process -FilePath $exe
    }
    "ax-smoke-windows" {
        $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\windows-ax-smoke.ps1")
        if (-not $Live) {
            $args += "-StaticOnly"
        }
        Invoke-CommandChecked -FilePath pwsh -Arguments $args
    }
    "publish-windows" {
        Invoke-CommandChecked -FilePath $DotNet -Arguments @("publish", "Apps\Windows\GUIForCLIWindows\GUIForCLIWindows.csproj", "-c", "Release", "-o", "out\windows-publish", "-p:Platform=x64", "-p:WindowsAppSDKSelfContained=true", "-p:SelfContained=true")
    }
    "package-windows-msix" {
        $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\package-windows-msix.ps1", "-DotNet", $DotNet)
        if ($Cert) {
            $args += @("-CertificatePath", $Cert, "-CertificatePassword", $CertPassword)
        }
        Invoke-CommandChecked -FilePath pwsh -Arguments $args
    }
    default {
        Write-Error "Unknown target '$Target'. Run '.\make.ps1 help' for available targets."
        exit 2
    }
}
