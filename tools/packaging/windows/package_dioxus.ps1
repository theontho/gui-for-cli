$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot "..\..\.."))

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

Invoke-Checked -FilePath npm -Arguments @("--prefix", "platform/typescript", "run", "build")
Invoke-Checked -FilePath npm -Arguments @("--prefix", "platform/typescript", "run", "tauri:prepare-node")
Invoke-Checked -FilePath cargo -Arguments @("build", "--release", "--manifest-path", "exp-platform\rust\dioxus-shell\Cargo.toml")

$packageRoot = Join-Path $PWD "out\windows-dioxus\package"
$zipPath = Join-Path $PWD "out\windows-dioxus\GUIForCLIDioxus-win-x64.zip"
if (Test-Path $packageRoot) {
    Remove-Item -Recurse -Force $packageRoot
}
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "platform\typescript\web") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "examples") | Out-Null
Copy-Item "exp-platform\rust\dioxus-shell\target\release\gui-for-cli-webui-dioxus.exe" (Join-Path $packageRoot "gui-for-cli-webui-dioxus.exe")
Copy-Item "platform\typescript\dist" (Join-Path $packageRoot "platform\typescript\dist") -Recurse
Copy-Item "platform\typescript\web\vendor" (Join-Path $packageRoot "platform\typescript\web\vendor") -Recurse
Copy-Item "platform\typescript\web\index.html" (Join-Path $packageRoot "platform\typescript\web\index.html")
Copy-Item "platform\typescript\web\styles.css" (Join-Path $packageRoot "platform\typescript\web\styles.css")
Copy-Item "platform\typescript\web\packagers\tauri\resources\node" (Join-Path $packageRoot "node") -Recurse
Copy-Item "examples\WGSExtract" (Join-Path $packageRoot "examples\WGSExtract") -Recurse
Copy-Item "resources" (Join-Path $packageRoot "resources") -Recurse
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath
"Wrote $zipPath"
