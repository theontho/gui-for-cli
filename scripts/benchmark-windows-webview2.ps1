param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [string[]]$AppArguments = @("--webview-shell"),
    [string]$RepoRoot = "",
    [string]$NodePath = "",
    [int]$Iterations = 7,
    [double]$SampleSeconds = 15.0,
    [double]$ReadyTimeoutSeconds = 20.0
)

$ErrorActionPreference = "Stop"

if ($Iterations -le 0) {
    Write-Warning "Iterations must be positive. Using 3."
    $Iterations = 3
} elseif (($Iterations % 2) -eq 0) {
    Write-Warning "Iterations should be odd for median sampling. Using $($Iterations + 1)."
    $Iterations += 1
}

if ($SampleSeconds -le 0) {
    Write-Warning "SampleSeconds must be positive. Using 15.0."
    $SampleSeconds = 15.0
}

if ($ReadyTimeoutSeconds -le 0) {
    Write-Warning "ReadyTimeoutSeconds must be positive. Using 20.0."
    $ReadyTimeoutSeconds = 20.0
}

if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Executable must be a file path: $Executable"
}
$resolvedExecutable = (Resolve-Path -LiteralPath $Executable).Path

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

if (-not [string]::IsNullOrWhiteSpace($NodePath)) {
    $NodePath = (Resolve-Path -LiteralPath $NodePath).Path
} else {
    $NodePath = (Get-Command node -ErrorAction Stop).Source
}

$processorCount = [Environment]::ProcessorCount

function Get-DirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return 0
    }

    return (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object Length -Sum).Sum
}

function Get-Median {
    param([Parameter(Mandatory = $true)][double[]]$Values)
    if ($Values.Count -eq 0) {
        return 0.0
    }
    $sorted = @($Values | Sort-Object)
    return $sorted[[int][math]::Floor($sorted.Count / 2)]
}

function Get-DescendantProcessIds {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $processTable = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
    $pending = [System.Collections.Generic.List[int]]::new()
    $visited = @{}
    $pending.Add($RootProcessId)

    while ($pending.Count -gt 0) {
        $current = $pending[0]
        $pending.RemoveAt(0)
        if ($visited.ContainsKey($current)) {
            continue
        }
        $visited[$current] = $true

        foreach ($child in $processTable) {
            if ($child.ParentProcessId -eq $current) {
                $pending.Add([int]$child.ProcessId)
            }
        }
    }

    return @($visited.Keys | ForEach-Object { [int]$_ } | Sort-Object)
}

function Get-ProcessSetSnapshot {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $ids = Get-DescendantProcessIds -RootProcessId $RootProcessId
    $workingSetBytes = 0.0
    $privateBytes = 0.0
    $cpuSeconds = 0.0
    $liveIds = @()

    foreach ($id in $ids) {
        $process = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        $liveIds += $id
        $workingSetBytes += $process.WorkingSet64
        $privateBytes += $process.PrivateMemorySize64
        $cpuSeconds += $process.TotalProcessorTime.TotalSeconds
    }

    return [ordered]@{
        processIds = $liveIds
        processCount = $liveIds.Count
        workingSetBytes = [double]$workingSetBytes
        privateBytes = [double]$privateBytes
        cpuSeconds = [double]$cpuSeconds
    }
}

function Stop-ProcessSet {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $ids = Get-DescendantProcessIds -RootProcessId $RootProcessId
    foreach ($id in ($ids | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Start-BenchmarkProcess {
    param([bool]$ExitAfterReady)

    $stdoutPath = Join-Path $env:TEMP ("gui-for-cli-webview2-benchmark-{0}-stdout.log" -f [guid]::NewGuid().ToString("N"))
    $stderrPath = Join-Path $env:TEMP ("gui-for-cli-webview2-benchmark-{0}-stderr.log" -f [guid]::NewGuid().ToString("N"))
    $environment = @{
        GFC_REPO_ROOT = $RepoRoot
        GFC_NODE_PATH = $NodePath
    }
    if ($ExitAfterReady) {
        $environment["GFC_BENCH_EXIT_AFTER_READY"] = "1"
    }

    $process = Start-Process `
        -FilePath $resolvedExecutable `
        -ArgumentList $AppArguments `
        -WorkingDirectory (Split-Path -Parent $resolvedExecutable) `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Environment $environment

    return [pscustomobject]@{
        Process = $process
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Read-BenchmarkOutput {
    param($ProcessState)

    $metrics = [ordered]@{}
    $errorLines = New-Object System.Collections.Generic.List[string]

    $lines = @()
    if (Test-Path -LiteralPath $ProcessState.StdoutPath) {
        $lines += Get-Content -LiteralPath $ProcessState.StdoutPath
    }
    if (Test-Path -LiteralPath $ProcessState.StderrPath) {
        $lines += Get-Content -LiteralPath $ProcessState.StderrPath
    }

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -match '^metric\s+([a-zA-Z0-9]+)_ms=([0-9]+(?:\.[0-9]+)?)') {
            $metrics[$Matches[1]] = [double]$Matches[2]
            continue
        }
        if ($line -like 'error=*') {
            $errorLines.Add($line)
        }
    }

    return [pscustomobject]@{
        Metrics = $metrics
        ErrorLines = $errorLines
    }
}

function Remove-BenchmarkLogs {
    param($ProcessState)
    Remove-Item -LiteralPath $ProcessState.StdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ProcessState.StderrPath -Force -ErrorAction SilentlyContinue
}

$startupRuns = @()
for ($index = 0; $index -lt $Iterations; $index++) {
    $state = Start-BenchmarkProcess -ExitAfterReady $true
    $process = $state.Process
    try {
        if (-not $process.WaitForExit([int](($ReadyTimeoutSeconds + 10.0) * 1000.0))) {
            Stop-ProcessSet -RootProcessId $process.Id
            throw "Timed out waiting for benchmark startup run $($index + 1) to exit."
        }
        $process.WaitForExit()
        $output = Read-BenchmarkOutput -ProcessState $state
        $metrics = @{}
        foreach ($entry in $output.Metrics.GetEnumerator()) {
            $metrics[$entry.Key] = [math]::Round([double]$entry.Value, 1)
        }
        if (-not $metrics.Contains("webAppRendered")) {
            $errors = [string]::Join("; ", $output.ErrorLines.ToArray())
            throw "Startup run $($index + 1) did not reach webAppRendered metric. $errors"
        }
        $startupRuns += [ordered]@{
            iteration = $index + 1
            metrics = $metrics
        }
    }
    finally {
        Remove-BenchmarkLogs -ProcessState $state
        $process.Dispose()
    }
}

$startupByMetric = @{}
foreach ($run in $startupRuns) {
    foreach ($metricName in $run.metrics.Keys) {
        if (-not $startupByMetric.ContainsKey($metricName)) {
            $startupByMetric[$metricName] = New-Object System.Collections.Generic.List[double]
        }
        $startupByMetric[$metricName].Add([double]$run.metrics[$metricName])
    }
}

$startupMedians = [ordered]@{}
$startupSamples = [ordered]@{}
foreach ($metricName in ($startupByMetric.Keys | Sort-Object)) {
    $values = @($startupByMetric[$metricName].ToArray())
    $startupSamples["${metricName}Milliseconds"] = @($values | ForEach-Object { [math]::Round($_, 1) })
    $startupMedians["${metricName}Milliseconds"] = [math]::Round((Get-Median -Values $values), 1)
}

$idleState = Start-BenchmarkProcess -ExitAfterReady $false
$idleProcess = $idleState.Process
try {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($idleProcess.HasExited) {
            $output = Read-BenchmarkOutput -ProcessState $idleState
            $errors = [string]::Join("; ", $output.ErrorLines.ToArray())
            throw "Idle benchmark process exited before sampling. Exit code: $($idleProcess.ExitCode). $errors"
        }
        $idleProcess.Refresh()
        if ($idleProcess.MainWindowHandle -ne [IntPtr]::Zero) {
            break
        }
        Start-Sleep -Milliseconds 25
    }

    if ($idleProcess.MainWindowHandle -eq [IntPtr]::Zero) {
        throw "Timed out waiting for main window for idle benchmark run."
    }

    Start-Sleep -Milliseconds 500
    $before = Get-ProcessSetSnapshot -RootProcessId $idleProcess.Id
    $sampleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds ([int]($SampleSeconds * 1000.0))
    $after = Get-ProcessSetSnapshot -RootProcessId $idleProcess.Id
    $elapsedSeconds = [math]::Max($sampleStopwatch.Elapsed.TotalSeconds, 0.001)
    $cpuDelta = [math]::Max(0.0, ($after.cpuSeconds - $before.cpuSeconds))
    $cpuPercentAllCores = ($cpuDelta / ($elapsedSeconds * $processorCount)) * 100.0

    $idleSample = [ordered]@{
        sampleSeconds = [math]::Round($elapsedSeconds, 1)
        cpuPercentAllCores = [math]::Round($cpuPercentAllCores, 2)
        workingSetMB = [math]::Round($after.workingSetBytes / 1MB, 1)
        privateMemoryMB = [math]::Round($after.privateBytes / 1MB, 1)
        processCount = $after.processCount
    }
}
finally {
    Stop-ProcessSet -RootProcessId $idleProcess.Id
    Remove-BenchmarkLogs -ProcessState $idleState
    $idleProcess.Dispose()
}

$publishDirectory = Split-Path -Parent $resolvedExecutable
$publishBytes = Get-DirectorySize -Path $publishDirectory
$exeBytes = (Get-Item -LiteralPath $resolvedExecutable).Length

[ordered]@{
    executable = $resolvedExecutable
    appArguments = $AppArguments
    iterations = $Iterations
    startupRuns = $startupRuns
    startupSamples = $startupSamples
    startupMedians = $startupMedians
    idleSample = $idleSample
    sizes = [ordered]@{
        publishDirectoryMB = [math]::Round($publishBytes / 1MB, 2)
        executableMB = [math]::Round($exeBytes / 1MB, 2)
    }
} | ConvertTo-Json -Depth 8
