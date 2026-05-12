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
    "build-dioxus" = "Build the Dioxus Native WebUI shell."
    "run-dioxus" = "Run the Dioxus Native WebUI shell against the source tree."
    "package-dioxus" = "Build a portable Dioxus Native WebUI package for benchmarking."
    "ax-smoke" = "Run a static UI Automation smoke check, or pass -Live for a running app."
    "publish" = "Publish the native app into out\\windows-publish. Local/manual only."
    "package-msix" = "Build an MSIX package. Set -Cert and -CertPassword for signed packages."
    "package-bootstrap" = "Build a framework-dependent app payload ZIP for runtime-downloading installers."
    "package-webui" = "Build a portable WebUI package with node.exe, assets, built-in strings, and the default bundle."
    "package-electron" = "Build a packaged Electron WebUI app for benchmark and packaging comparisons."
    "test-flutter" = "Run Flutter app tests."
    "build-flutter-windows" = "Build the Flutter Windows desktop app. Requires Flutter on PATH."
    "benchmark-flutter" = "Run the Flutter Windows app benchmark set."
    "build-slint" = "Build the Rust Slint desktop app in release mode."
    "run-slint" = "Build and run the Rust Slint desktop app."
    "benchmark-slint" = "Build and run the Rust Slint full-feature benchmark."
    "package-slint" = "Build a portable Rust Slint app package with the default bundle."
    "build-imgui" = "Build the Rust Dear ImGui desktop app in release mode."
    "run-imgui" = "Build and run the Rust Dear ImGui desktop app."
    "benchmark-imgui" = "Build and run the Rust Dear ImGui full-feature benchmark."
    "package-imgui" = "Build a portable Rust Dear ImGui app package with the default bundle."
    "package-gio" = "Build a portable Go Gio app package for benchmark comparisons."
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
    "build-dioxus" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "build")
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--release", "--manifest-path", "Apps\DioxusShell\Cargo.toml")
    }
    "run-dioxus" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "build")
        $node = (Get-Command node -ErrorAction Stop).Source
        $previousRepoRoot = $env:GFC_REPO_ROOT
        $previousNodePath = $env:GFC_NODE_PATH
        $env:GFC_REPO_ROOT = $PSScriptRoot
        $env:GFC_NODE_PATH = $node
        try {
            Invoke-CommandChecked -FilePath cargo -Arguments @("run", "--release", "--manifest-path", "Apps\DioxusShell\Cargo.toml")
        }
        finally {
            if ($null -ne $previousRepoRoot) {
                $env:GFC_REPO_ROOT = $previousRepoRoot
            }
            else {
                Remove-Item Env:GFC_REPO_ROOT -ErrorAction SilentlyContinue
            }
            if ($null -ne $previousNodePath) {
                $env:GFC_NODE_PATH = $previousNodePath
            }
            else {
                Remove-Item Env:GFC_NODE_PATH -ErrorAction SilentlyContinue
            }
        }
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
    "package-dioxus" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "build")
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "tauri:prepare-node")
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--release", "--manifest-path", "Apps\DioxusShell\Cargo.toml")
        $packageRoot = Join-Path $PSScriptRoot "out\windows-dioxus\package"
        if (Test-Path $packageRoot) {
            Remove-Item -Recurse -Force $packageRoot
        }
        New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "WebUI") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Examples") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Sources\GUIForCLICore\Resources") | Out-Null
        Copy-Item "Apps\DioxusShell\target\release\gui-for-cli-webui-dioxus.exe" (Join-Path $packageRoot "gui-for-cli-webui-dioxus.exe")
        Copy-Item "WebUI\dist" (Join-Path $packageRoot "WebUI\dist") -Recurse
        Copy-Item "WebUI\vendor" (Join-Path $packageRoot "WebUI\vendor") -Recurse
        Copy-Item "WebUI\index.html" (Join-Path $packageRoot "WebUI\index.html")
        Copy-Item "WebUI\styles.css" (Join-Path $packageRoot "WebUI\styles.css")
        Copy-Item "WebUI\src-tauri\resources\node" (Join-Path $packageRoot "node") -Recurse
        Copy-Item "Examples\WGSExtract" (Join-Path $packageRoot "Examples\WGSExtract") -Recurse
        Copy-Item "Sources\GUIForCLICore\Resources\BuiltinStrings" (Join-Path $packageRoot "Sources\GUIForCLICore\Resources\BuiltinStrings") -Recurse
        $zipPath = Join-Path $PSScriptRoot "out\windows-dioxus\GUIForCLIDioxus-win-x64.zip"
        if (Test-Path $zipPath) {
            Remove-Item -Force $zipPath
        }
        Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath
    }
    "test-flutter" {
        Push-Location Apps\Flutter
        try {
            Invoke-CommandChecked -FilePath flutter -Arguments @("test")
        }
        finally {
            Pop-Location
        }
    }
    "build-flutter-windows" {
        Push-Location Apps\Flutter
        try {
            Invoke-CommandChecked -FilePath flutter -Arguments @("create", "--platforms=windows", "--project-name", "gui_for_cli_flutter", ".")
            Invoke-CommandChecked -FilePath flutter -Arguments @("build", "windows", "--release", "--dart-define=GFC_REPO_ROOT=$PSScriptRoot", "--dart-define=GFC_BUNDLE_ROOT=$(Join-Path $PSScriptRoot 'Examples\WGSExtract')")
        }
        finally {
            Pop-Location
        }
    }
    "benchmark-flutter" {
        Invoke-CommandChecked -FilePath pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\benchmark-flutter.ps1")
    }
    "build-slint" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\Slint\Cargo.toml", "--release")
    }
    "run-slint" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\Slint\Cargo.toml", "--release")
        Invoke-CommandChecked -FilePath "Apps\Slint\target\release\gui-for-cli-slint.exe" -Arguments @("--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    "benchmark-slint" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\Slint\Cargo.toml", "--release")
        $previousOffline = $env:GUI_FOR_CLI_OFFLINE
        $env:GUI_FOR_CLI_OFFLINE = "1"
        try {
            Invoke-CommandChecked -FilePath "Apps\Slint\target\release\gui-for-cli-slint.exe" -Arguments @("--bundle", (Resolve-Path "Examples\WGSExtract"), "--benchmark", "--benchmark-full", "--once")
        }
        finally {
            $env:GUI_FOR_CLI_OFFLINE = $previousOffline
        }
    }
    "package-slint" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\Slint\Cargo.toml", "--release")
        $packageRoot = Join-Path $PSScriptRoot "out\windows-slint\package"
        $zipPath = Join-Path $PSScriptRoot "out\windows-slint\GUIForCLISlint-win-x64.zip"
        if (Test-Path $packageRoot) {
            Remove-Item -Recurse -Force $packageRoot
        }
        if (Test-Path $zipPath) {
            Remove-Item -Force $zipPath
        }
        New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Examples") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Sources\GUIForCLICore\Resources") | Out-Null
        Copy-Item "Apps\Slint\target\release\gui-for-cli-slint.exe" (Join-Path $packageRoot "gui-for-cli-slint.exe")
        Copy-Item -Recurse "Examples\WGSExtract" (Join-Path $packageRoot "Examples\WGSExtract")
        Copy-Item -Recurse "Sources\GUIForCLICore\Resources\BuiltinStrings" (Join-Path $packageRoot "Sources\GUIForCLICore\Resources\BuiltinStrings")
        Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath
        "Wrote $zipPath"
    }
    "build-imgui" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\ImGui\Cargo.toml", "--release")
    }
    "run-imgui" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\ImGui\Cargo.toml", "--release")
        Invoke-CommandChecked -FilePath "Apps\ImGui\target\release\gui-for-cli-imgui.exe" -Arguments @("--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    "benchmark-imgui" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\ImGui\Cargo.toml", "--release")
        $previousOffline = $env:GUI_FOR_CLI_OFFLINE
        $env:GUI_FOR_CLI_OFFLINE = "1"
        try {
            Invoke-CommandChecked -FilePath "Apps\ImGui\target\release\gui-for-cli-imgui.exe" -Arguments @("--bundle", (Resolve-Path "Examples\WGSExtract"), "--benchmark", "--benchmark-full", "--once")
        }
        finally {
            $env:GUI_FOR_CLI_OFFLINE = $previousOffline
        }
    }
    "package-imgui" {
        Invoke-CommandChecked -FilePath cargo -Arguments @("build", "--manifest-path", "Apps\ImGui\Cargo.toml", "--release")
        $packageRoot = Join-Path $PSScriptRoot "out\windows-imgui\package"
        $zipPath = Join-Path $PSScriptRoot "out\windows-imgui\GUIForCLIImGui-win-x64.zip"
        if (Test-Path $packageRoot) {
            Remove-Item -Recurse -Force $packageRoot
        }
        if (Test-Path $zipPath) {
            Remove-Item -Force $zipPath
        }
        New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Examples") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Sources\GUIForCLICore\Resources") | Out-Null
        Copy-Item "Apps\ImGui\target\release\gui-for-cli-imgui.exe" (Join-Path $packageRoot "gui-for-cli-imgui.exe")
        Copy-Item -Recurse "Examples\WGSExtract" (Join-Path $packageRoot "Examples\WGSExtract")
        Copy-Item -Recurse "Sources\GUIForCLICore\Resources\BuiltinStrings" (Join-Path $packageRoot "Sources\GUIForCLICore\Resources\BuiltinStrings")
        Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath
        "Wrote $zipPath"
    }
    "nodegui" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "nodegui", "--", "--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    "nodegui-smoke" {
        Invoke-CommandChecked -FilePath npm -Arguments @("--prefix", "WebUI", "run", "nodegui:smoke", "--", "--bundle", (Resolve-Path "Examples\WGSExtract"))
    }
    "package-gio" {
        Invoke-CommandChecked -FilePath pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts\package-windows-gio.ps1")
    }
    default {
        Write-Error "Unknown target '$Target'. Run '.\make.ps1 help' for available targets."
        exit 2
    }
}
