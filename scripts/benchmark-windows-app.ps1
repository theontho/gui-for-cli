param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [int]$Iterations = 7,
    [double]$SampleSeconds = 15.0,
    [double]$ReadyTimeoutSeconds = 10.0
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
    Write-Warning "ReadyTimeoutSeconds must be positive. Using 10.0."
    $ReadyTimeoutSeconds = 10.0
}

if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Executable must be a file path: $Executable"
}
$resolvedExecutable = Resolve-Path -LiteralPath $Executable
$processorCount = [Environment]::ProcessorCount

function Get-DirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return 0
    }

    return (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object Length -Sum).Sum
}

function Wait-AppWindowReady {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][double]$TimeoutSeconds
    )

    $start = [System.Diagnostics.Stopwatch]::StartNew()
    while ($start.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($Process.HasExited) {
            throw "App exited before a window was ready. Exit code: $($Process.ExitCode)"
        }

        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $start.Elapsed.TotalMilliseconds
        }

        Start-Sleep -Milliseconds 25
    }

    throw "Timed out after $TimeoutSeconds seconds waiting for a main window."
}

function Stop-AppProcess {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }

    if (-not $Process.CloseMainWindow()) {
        Stop-Process -Id $Process.Id -Force
        return
    }

    if (-not $Process.WaitForExit(3000)) {
        Stop-Process -Id $Process.Id -Force
    }
}

$startupSamples = @()
$lastProcessSample = $null

for ($index = 0; $index -lt $Iterations; $index++) {
    $process = Start-Process -FilePath $resolvedExecutable.Path -PassThru
    try {
        $readyMilliseconds = Wait-AppWindowReady -Process $process -TimeoutSeconds $ReadyTimeoutSeconds
        $startupSamples += [math]::Round($readyMilliseconds, 1)

        if ($index -eq $Iterations - 1) {
            $process.Refresh()
            $cpuStart = $process.TotalProcessorTime
            $sampleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Milliseconds ([int]($SampleSeconds * 1000))
            $process.Refresh()
            $cpuEnd = $process.TotalProcessorTime
            $elapsedSeconds = [math]::Max($sampleStopwatch.Elapsed.TotalSeconds, 0.001)
            $cpuPercentAllCores = (($cpuEnd - $cpuStart).TotalSeconds / ($elapsedSeconds * $processorCount)) * 100.0

            $lastProcessSample = [ordered]@{
                sampleSeconds = [math]::Round($elapsedSeconds, 1)
                cpuPercentAllCores = [math]::Round($cpuPercentAllCores, 2)
                workingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
                privateMemoryMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
                processCount = 1
            }
        }
    } finally {
        Stop-AppProcess -Process $process
    }
}

$sortedStartupSamples = @($startupSamples | Sort-Object)
$medianStartup = $sortedStartupSamples[[int][math]::Floor($sortedStartupSamples.Count / 2)]
$averageStartup = ($startupSamples | Measure-Object -Average).Average
$publishDirectory = Split-Path $resolvedExecutable.Path -Parent
$publishBytes = Get-DirectorySize -Path $publishDirectory
$exeBytes = (Get-Item -LiteralPath $resolvedExecutable.Path).Length

[ordered]@{
    executable = $resolvedExecutable.Path
    iterations = $Iterations
    startupReadyMilliseconds = $startupSamples
    averageStartupReadyMilliseconds = [math]::Round($averageStartup, 1)
    medianStartupReadyMilliseconds = $medianStartup
    idleSample = $lastProcessSample
    sizes = [ordered]@{
        publishDirectoryMB = [math]::Round($publishBytes / 1MB, 2)
        executableMB = [math]::Round($exeBytes / 1MB, 2)
    }
} | ConvertTo-Json -Depth 5
