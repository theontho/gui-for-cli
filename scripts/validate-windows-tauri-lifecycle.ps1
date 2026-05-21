param(
    [string]$InstallerPath = "",
    [string]$InstallDirectory = "$env:LOCALAPPDATA\WGSExtract",
    [string]$WorkspaceDirectory = "$env:USERPROFILE\.local\share\dev.guiforcli.web.embed.wgsextract\BundleWorkspaces\wgs-extract",
    [string]$LogDirectory = "tmp\tauri-lifecycle",
    [int]$InstallTimeoutSeconds = 180,
    [int]$StartupTimeoutSeconds = 60,
    [int]$SetupTimeoutSeconds = 1800,
    [int]$ShutdownTimeoutSeconds = 30,
    [switch]$SkipSetup,
    [switch]$KeepInstalled
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))

$script:StartedAt = Get-Date
$script:StageResults = [System.Collections.Generic.List[object]]::new()
$LogDirectory = (New-Item -ItemType Directory -Force -Path $LogDirectory).FullName
$PortFile = Join-Path $LogDirectory "installed-tauri-port.txt"
$SetupLog = Join-Path $LogDirectory "installed-setup.ndjson"
$SetupSummary = Join-Path $LogDirectory "installed-setup-summary.json"
$UninstallLog = Join-Path $LogDirectory "installed-uninstall.ndjson"
$UninstallSummary = Join-Path $LogDirectory "installed-uninstall-summary.json"

function Resolve-InstallerPath {
    if ($InstallerPath) {
        return (Resolve-Path $InstallerPath).Path
    }

    $candidates = @(
        Get-ChildItem -LiteralPath "out\release\tauri" -Filter "*-setup.exe" -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath "platform\typescript\web\packagers\tauri\target\release\bundle\nsis" -Filter "*-setup.exe" -File -ErrorAction SilentlyContinue
    ) | Sort-Object LastWriteTimeUtc -Descending
    if ($candidates.Count -eq 0) {
        throw "No Tauri NSIS installer was found under out\release\tauri or the Tauri target bundle directory."
    }
    return $candidates[0].FullName
}

function Write-Stage {
    param([string]$Name, [string]$Status = "start", [string]$Detail = "")

    $elapsed = [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds, 1)
    $message = "[$elapsed s] [$Status] $Name"
    if ($Detail) {
        $message = "$message - $Detail"
    }
    Write-Host $message
}

function Complete-Stage {
    param([string]$Name, [datetime]$Started, [string]$Detail = "")

    $duration = [math]::Round(((Get-Date) - $Started).TotalSeconds, 1)
    $script:StageResults.Add([ordered]@{ name = $Name; status = "ok"; seconds = $duration; detail = $Detail })
    Write-Stage -Name $Name -Status "ok" -Detail "$duration s $Detail"
}

function Fail-Stage {
    param([string]$Name, [datetime]$Started, [string]$Detail)

    $duration = [math]::Round(((Get-Date) - $Started).TotalSeconds, 1)
    $script:StageResults.Add([ordered]@{ name = $Name; status = "failed"; seconds = $duration; detail = $Detail })
    Write-Stage -Name $Name -Status "failed" -Detail $Detail
    Write-Summary
    throw $Detail
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8NoBom)
}

function Write-Summary {
    $summaryPath = Join-Path $LogDirectory "summary.json"
    $summary = [ordered]@{
        startedAt = $script:StartedAt.ToString("o")
        completedAt = (Get-Date).ToString("o")
        stages = $script:StageResults
        installDirectory = $InstallDirectory
        workspaceDirectory = $WorkspaceDirectory
        setupLog = $SetupLog
        setupSummary = $SetupSummary
        uninstallLog = $UninstallLog
        uninstallSummary = $UninstallSummary
    }
    Write-Utf8File -LiteralPath $summaryPath -Value (($summary | ConvertTo-Json -Depth 8) + "`n")
    Write-Host "Summary: $summaryPath"
}

function Invoke-Stage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    $started = Get-Date
    Write-Stage -Name $Name
    try {
        $detail = & $ScriptBlock
        Complete-Stage -Name $Name -Started $started -Detail ([string]$detail)
    }
    catch {
        Fail-Stage -Name $Name -Started $started -Detail $_.Exception.Message
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 120,
        [string]$WorkingDirectory = (Get-Location).Path,
        [hashtable]$Environment = @{},
        [string]$Name = (Split-Path -Leaf $FilePath)
    )

    $stdoutPath = Join-Path $LogDirectory "$($Name -replace '[^A-Za-z0-9_.-]', '_').stdout.log"
    $stderrPath = Join-Path $LogDirectory "$($Name -replace '[^A-Za-z0-9_.-]', '_').stderr.log"
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }
    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = [string]$Environment[$key]
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Name timed out after $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Write-Utf8File -LiteralPath $stdoutPath -Value $stdout
    Write-Utf8File -LiteralPath $stderrPath -Value $stderr
    if ($process.ExitCode -ne 0) {
        throw "$Name exited $($process.ExitCode). stdout=$stdoutPath stderr=$stderrPath"
    }
    return [ordered]@{ stdout = $stdoutPath; stderr = $stderrPath; exitCode = $process.ExitCode }
}

function Get-TargetProcesses {
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -like "*WGSExtract*" -or
            $_.CommandLine -like "*gui-for-cli-webui-tauri*" -or
            $_.CommandLine -like "*BundleWorkspaces\\wgs-extract*" -or
            $_.CommandLine -like "*BundleWorkspaces/wgs-extract*"
        )
    } | Select-Object ProcessId, ParentProcessId, Name, CommandLine
}

function Stop-TargetProcesses {
    $processes = @(Get-TargetProcesses)
    foreach ($process in $processes) {
        if ($process.ProcessId -ne $PID) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
    $remaining = @(Get-TargetProcesses)
    if ($remaining.Count -gt 0) {
        throw "Target processes still running: $($remaining.ProcessId -join ', ')"
    }
    return "stopped $($processes.Count) process(es)"
}

function Assert-Exists {
    param([string[]]$Paths)

    $missing = @($Paths | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        throw "Missing expected path(s): $($missing -join '; ')"
    }
}

function Assert-NotExists {
    param([string[]]$Paths)

    $present = @($Paths | Where-Object { Test-Path -LiteralPath $_ })
    if ($present.Count -gt 0) {
        throw "Unexpected remaining path(s): $($present -join '; ')"
    }
}

function Remove-Tree {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    for ($attempt = 1; $attempt -le 5; $attempt += 1) {
        if (-not (Test-Path -LiteralPath $LiteralPath)) {
            return
        }
        try {
            Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if (-not (Test-Path -LiteralPath $LiteralPath)) {
                return
            }
            if ($attempt -eq 5) {
                throw
            }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
}

function Install-App {
    $resolvedInstaller = Resolve-InstallerPath
    Invoke-External -FilePath $resolvedInstaller -Arguments @("/S") -TimeoutSeconds $InstallTimeoutSeconds -Name "install" | Out-Null
    Assert-Exists -Paths @(
        $InstallDirectory,
        (Join-Path $InstallDirectory "gui-for-cli-webui-tauri.exe"),
        (Join-Path $InstallDirectory "uninstall.exe"),
        (Join-Path $InstallDirectory "node\node.exe"),
        (Join-Path $InstallDirectory "examples\EmbeddedBundle")
    )
    return $InstallDirectory
}

function Uninstall-App {
    $uninstaller = Join-Path $InstallDirectory "uninstall.exe"
    if (Test-Path -LiteralPath $uninstaller) {
        Invoke-External -FilePath $uninstaller -Arguments @("/S") -TimeoutSeconds $InstallTimeoutSeconds -Name "uninstall" | Out-Null
    }
    Remove-Tree -LiteralPath $InstallDirectory
    Assert-NotExists -Paths @($InstallDirectory)
    return $InstallDirectory
}

function Clear-InstallData {
    foreach ($path in @($InstallDirectory, "$env:LOCALAPPDATA\GUI for CLI WebUI", $WorkspaceDirectory)) {
        Remove-Tree -LiteralPath $path
    }
    Assert-NotExists -Paths @($InstallDirectory, "$env:LOCALAPPDATA\GUI for CLI WebUI", $WorkspaceDirectory)
    return "cleared"
}

function Start-InstalledApp {
    Remove-Item -LiteralPath $PortFile -ErrorAction SilentlyContinue
    $appPath = Join-Path $InstallDirectory "gui-for-cli-webui-tauri.exe"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $appPath
    $psi.WorkingDirectory = $InstallDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($null -ne $psi.Environment) {
        $psi.Environment["GFC_PORT_FILE"] = $PortFile
    } else {
        $psi.EnvironmentVariables["GFC_PORT_FILE"] = $PortFile
    }
    $process = [System.Diagnostics.Process]::Start($psi)

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            throw "Installed app exited during startup with code $($process.ExitCode)."
        }
        if (Test-Path -LiteralPath $PortFile) {
            $port = (Get-Content -LiteralPath $PortFile -Raw).Trim()
            if ($port) {
                return [ordered]@{ process = $process; port = [int]$port }
            }
        }
        Start-Sleep -Milliseconds 250
    }

    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Installed app did not write port file within $StartupTimeoutSeconds seconds."
}

function Invoke-SetupValidation {
    param([int]$Port)

    if ($SkipSetup) {
        return "skipped"
    }

    $nodePath = Join-Path (Resolve-Path ".node\node-v24.15.0-win-x64").Path "node.exe"
    $helper = Join-Path $LogDirectory "stream-setup.mjs"
    $helperSource = @'
import { writeFileSync } from 'node:fs';

const port = process.env.TEST_PORT;
const logPath = process.env.SETUP_LOG;
const summaryPath = process.env.SETUP_SUMMARY;
const timeoutMs = Number(process.env.SETUP_TIMEOUT_SECONDS ?? '1800') * 1000;
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(new Error('setup timeout')), timeoutMs);

try {
  const response = await fetch(`http://127.0.0.1:${port}/api/setup/stream`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ locale: '' }),
    signal: controller.signal,
  });
  if (!response.ok) {
    throw new Error(`setup HTTP ${response.status}: ${await response.text()}`);
  }
  const decoder = new TextDecoder();
  let buffer = '';
  let log = '';
  let complete;
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      log += `${line}\n`;
      const event = JSON.parse(line);
      if (event.type === 'complete') complete = event.result;
    }
  }
  if (buffer.trim()) {
    log += `${buffer}\n`;
    const event = JSON.parse(buffer);
    if (event.type === 'complete') complete = event.result;
  }
  writeFileSync(logPath, log, 'utf8');
  if (!complete) {
    throw new Error('setup stream ended without a complete event');
  }
  writeFileSync(summaryPath, `${JSON.stringify(complete, null, 2)}\n`, 'utf8');
  const failed = (complete.results ?? []).filter((result) => result.status !== 'ok');
  if (complete.status !== 'ok' || failed.length > 0) {
    console.error(`setup status=${complete.status}; failed=${failed.map((result) => `${result.id}:${result.status}:${result.exitCode}`).join(', ')}`);
    process.exit(1);
  }
} catch (error) {
  console.error(error?.message ?? String(error));
  process.exit(1);
} finally {
  clearTimeout(timeout);
}
'@
    Write-Utf8File -LiteralPath $helper -Value $helperSource
    Invoke-External `
        -FilePath $nodePath `
        -Arguments @($helper) `
        -TimeoutSeconds ($SetupTimeoutSeconds + 30) `
        -Environment @{
            TEST_PORT = $Port
            SETUP_LOG = $SetupLog
            SETUP_SUMMARY = $SetupSummary
            SETUP_TIMEOUT_SECONDS = $SetupTimeoutSeconds
        } `
        -Name "setup-stream" | Out-Null

    $runtime = Join-Path $WorkspaceDirectory "runtime\wgsextract-cli"
    Assert-Exists -Paths @(
        $WorkspaceDirectory,
        $runtime,
        (Join-Path $runtime "app"),
        (Join-Path $runtime "bin"),
        (Join-Path $runtime "bin\wgsextract.cmd")
    )
    return "setup ok"
}

function Invoke-UninstallValidation {
    param([int]$Port)

    $nodePath = Join-Path (Resolve-Path ".node\node-v24.15.0-win-x64").Path "node.exe"
    $helper = Join-Path $LogDirectory "stream-uninstall.mjs"
    $helperSource = @'
import { writeFileSync } from 'node:fs';

const port = process.env.TEST_PORT;
const logPath = process.env.UNINSTALL_LOG;
const summaryPath = process.env.UNINSTALL_SUMMARY;
const timeoutMs = Number(process.env.UNINSTALL_TIMEOUT_SECONDS ?? '1800') * 1000;
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(new Error('uninstall timeout')), timeoutMs);

try {
  const response = await fetch(`http://127.0.0.1:${port}/api/uninstall/stream`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ locale: '' }),
    signal: controller.signal,
  });
  if (!response.ok) {
    throw new Error(`uninstall HTTP ${response.status}: ${await response.text()}`);
  }
  const decoder = new TextDecoder();
  let buffer = '';
  let log = '';
  let complete;
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      log += `${line}\n`;
      const event = JSON.parse(line);
      if (event.type === 'complete') complete = event.result;
    }
  }
  if (buffer.trim()) {
    log += `${buffer}\n`;
    const event = JSON.parse(buffer);
    if (event.type === 'complete') complete = event.result;
  }
  writeFileSync(logPath, log, 'utf8');
  if (!complete) {
    throw new Error('uninstall stream ended without a complete event');
  }
  writeFileSync(summaryPath, `${JSON.stringify(complete, null, 2)}\n`, 'utf8');
  const failed = (complete.results ?? []).filter((result) => result.status !== 'ok');
  if (complete.status !== 'ok' || failed.length > 0) {
    console.error(`uninstall status=${complete.status}; failed=${failed.map((result) => `${result.id}:${result.status}:${result.exitCode}`).join(', ')}`);
    process.exit(1);
  }
} catch (error) {
  console.error(error?.message ?? String(error));
  process.exit(1);
} finally {
  clearTimeout(timeout);
}
'@
    Write-Utf8File -LiteralPath $helper -Value $helperSource
    Invoke-External `
        -FilePath $nodePath `
        -Arguments @($helper) `
        -TimeoutSeconds ($SetupTimeoutSeconds + 30) `
        -Environment @{
            TEST_PORT = $Port
            UNINSTALL_LOG = $UninstallLog
            UNINSTALL_SUMMARY = $UninstallSummary
            UNINSTALL_TIMEOUT_SECONDS = $SetupTimeoutSeconds
        } `
        -Name "uninstall-stream" | Out-Null

    Assert-NotExists -Paths @(
        (Join-Path $WorkspaceDirectory "runtime\wgsextract-cli")
    )
    return "bundle uninstall ok"
}

function Stop-InstalledApp {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process.HasExited) {
        [void]$Process.CloseMainWindow()
        if (-not $Process.WaitForExit($ShutdownTimeoutSeconds * 1000)) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            throw "Installed app did not exit within $ShutdownTimeoutSeconds seconds after window close."
        }
    }
    Start-Sleep -Seconds 2
    $remaining = @(Get-TargetProcesses)
    if ($remaining.Count -gt 0) {
        throw "Processes remained after close: $($remaining.ProcessId -join ', ')"
    }
    return "app exited and processes cleaned up"
}

$appState = $null
try {
    Invoke-Stage -Name "stop-existing-processes" -ScriptBlock { Stop-TargetProcesses }
    Invoke-Stage -Name "uninstall-existing" -ScriptBlock { Uninstall-App }
    Invoke-Stage -Name "clear-install-data" -ScriptBlock { Clear-InstallData }
    Invoke-Stage -Name "install" -ScriptBlock { Install-App }
    Invoke-Stage -Name "launch" -ScriptBlock {
        $script:appState = Start-InstalledApp
        "pid=$($script:appState.process.Id) port=$($script:appState.port)"
    }
    Invoke-Stage -Name "setup" -ScriptBlock { Invoke-SetupValidation -Port $script:appState.port }
    Invoke-Stage -Name "bundle-uninstall" -ScriptBlock { Invoke-UninstallValidation -Port $script:appState.port }
    Invoke-Stage -Name "close-window" -ScriptBlock { Stop-InstalledApp -Process $script:appState.process }
    if (-not $KeepInstalled) {
        Invoke-Stage -Name "uninstall" -ScriptBlock { Uninstall-App }
        Invoke-Stage -Name "post-uninstall-process-check" -ScriptBlock { Stop-TargetProcesses }
        Invoke-Stage -Name "clear-bundle-workspace" -ScriptBlock {
            Remove-Tree -LiteralPath $WorkspaceDirectory
            Assert-NotExists -Paths @($WorkspaceDirectory)
            "workspace removed"
        }
    }
    Write-Summary
}
catch {
    if ($appState -and $appState.process -and -not $appState.process.HasExited) {
        Stop-Process -Id $appState.process.Id -Force -ErrorAction SilentlyContinue
    }
    Stop-TargetProcesses | Out-Null
    throw
}
