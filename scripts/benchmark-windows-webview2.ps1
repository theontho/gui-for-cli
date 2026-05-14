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
    $pending = [System.Collections.Generic.Queue[int]]::new()
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    $pending.Enqueue($RootProcessId)

    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        if (-not $visited.Add($current)) {
            continue
        }

        foreach ($child in $processTable) {
            if ($child.ParentProcessId -eq $current) {
                $pending.Enqueue([int]$child.ProcessId)
            }
        }
    }

    return @($visited.ToArray() | Sort-Object)
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

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = Split-Path -Parent $resolvedExecutable
    foreach ($argument in $AppArguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment["GFC_REPO_ROOT"] = $RepoRoot
    $startInfo.Environment["GFC_NODE_PATH"] = $NodePath
    if ($ExitAfterReady) {
        $startInfo.Environment["GFC_BENCH_EXIT_AFTER_READY"] = "1"
    } else {
        $startInfo.Environment.Remove("GFC_BENCH_EXIT_AFTER_READY")
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $metrics = [ordered]@{}
    $errorLines = New-Object System.Collections.Generic.List[string]

    $stdoutHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ([string]::IsNullOrWhiteSpace($eventArgs.Data)) {
            return
        }
        if ($eventArgs.Data -match '^metric\s+([a-zA-Z0-9]+)_ms=([0-9]+(?:\.[0-9]+)?)') {
            $metrics[$Matches[1]] = [double]$Matches[2]
            return
        }
        if ($eventArgs.Data -like 'error=*') {
            $errorLines.Add($eventArgs.Data)
        }
    }
    $stderrHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if (-not [string]::IsNullOrWhiteSpace($eventArgs.Data)) {
            $errorLines.Add($eventArgs.Data)
        }
    }

    $process.add_OutputDataReceived($stdoutHandler)
    $process.add_ErrorDataReceived($stderrHandler)
    $null = $process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    return [pscustomobject]@{
        Process = $process
        Metrics = $metrics
        ErrorLines = $errorLines
        StdoutHandler = $stdoutHandler
        StderrHandler = $stderrHandler
    }
}

function Stop-BenchmarkReaders {
    param($ProcessState)
    $ProcessState.Process.remove_OutputDataReceived($ProcessState.StdoutHandler)
    $ProcessState.Process.remove_ErrorDataReceived($ProcessState.StderrHandler)
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
        Start-Sleep -Milliseconds 100
        $metrics = @{}
        foreach ($entry in $state.Metrics.GetEnumerator()) {
            $metrics[$entry.Key] = [math]::Round([double]$entry.Value, 1)
        }
        if (-not $metrics.Contains("webAppRendered")) {
            $errors = [string]::Join("; ", $state.ErrorLines.ToArray())
            throw "Startup run $($index + 1) did not reach webAppRendered metric. $errors"
        }
        $startupRuns += [ordered]@{
            iteration = $index + 1
            metrics = $metrics
        }
    }
    finally {
        Stop-BenchmarkReaders -ProcessState $state
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
            $errors = [string]::Join("; ", $idleState.ErrorLines.ToArray())
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
    $cpuPercentAllCores = (($after.cpuSeconds - $before.cpuSeconds) / ($elapsedSeconds * $processorCount)) * 100.0

    $idleSample = [ordered]@{
        sampleSeconds = [math]::Round($elapsedSeconds, 1)
        cpuPercentAllCores = [math]::Round($cpuPercentAllCores, 2)
        workingSetMB = [math]::Round($after.workingSetBytes / 1MB, 1)
        privateMemoryMB = [math]::Round($after.privateBytes / 1MB, 1)
        processCount = $after.processCount
    }
}
finally {
    Stop-BenchmarkReaders -ProcessState $idleState
    Stop-ProcessSet -RootProcessId $idleProcess.Id
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
