$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $scriptDir
$bundleRoot = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) {
    $env:GUI_FOR_CLI_BUNDLE_WORKSPACE
} else {
    Split-Path -Parent $scriptsRoot
}
$runtime = Join-Path $bundleRoot "runtime\wgsextract-cli"

function Stop-RuntimeProcesses {
    param([Parameter(Mandatory = $true)][string]$RuntimePath)

    $escapedRuntime = $RuntimePath.Replace("\", "\\")
    $processes = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and (
            $_.CommandLine -like "*$RuntimePath*" -or
            $_.CommandLine -like "*$escapedRuntime*"
        )
    })
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($processes.Count -gt 0) {
        Start-Sleep -Seconds 1
    }
}

function Remove-TreeWithRetry {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    for ($attempt = 1; $attempt -le 8; $attempt += 1) {
        if (-not (Test-Path -LiteralPath $LiteralPath)) {
            return
        }
        try {
            Get-ChildItem -LiteralPath $LiteralPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $_.Attributes = "Normal"
            }
            Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
            return
        } catch {
            Stop-RuntimeProcesses -RuntimePath $LiteralPath
            if ($attempt -eq 8) {
                throw
            }
            Start-Sleep -Milliseconds (500 * $attempt)
        }
    }
}

if (Test-Path -LiteralPath $runtime) {
    Stop-RuntimeProcesses -RuntimePath $runtime
    Remove-TreeWithRetry -LiteralPath $runtime
}
Write-Output "Removed WGS Extract runtime: $runtime"
