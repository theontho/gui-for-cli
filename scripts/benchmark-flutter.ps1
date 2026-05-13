param(
    [int]$Samples = 7,
    [string]$Bundle = "examples\WGSExtract",
    [string]$OutputDirectory = "out\flutter-benchmark"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot "exp-platform\dart\flutter"
$outputRoot = Join-Path $repoRoot $OutputDirectory
$stageRoot = Join-Path $outputRoot "project"
$resultPath = Join-Path $outputRoot "flutter-benchmark.json"

function Get-DirectorySize {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return 0
    }
    return (Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum
}

function Write-Result {
    param([hashtable]$Result)
    New-Item -ItemType Directory -Force $outputRoot | Out-Null
    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $Result | ConvertTo-Json -Depth 8
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Result @{
        scenario = "Flutter desktop app"
        status = "unavailable"
        reason = "flutter was not found on PATH"
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    exit 0
}

Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stageRoot | Out-Null
Copy-Item -Path (Join-Path $appRoot "*") -Destination $stageRoot -Recurse -Force

Push-Location $stageRoot
try {
    & flutter create --platforms=windows --project-name gui_for_cli_flutter . | Write-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Remove-Item -LiteralPath (Join-Path $stageRoot "test\widget_test.dart") -Force -ErrorAction SilentlyContinue

    & flutter pub get | Write-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & flutter test | Write-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $bundlePath = Resolve-Path (Join-Path $repoRoot $Bundle)
    & flutter build windows --release "--dart-define=GFC_REPO_ROOT=$repoRoot" "--dart-define=GFC_BUNDLE_ROOT=$bundlePath" | Write-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

$releaseRoot = Join-Path $stageRoot "build\windows\x64\runner\Release"
$exePath = Join-Path $releaseRoot "gui_for_cli_flutter.exe"
$startupSamples = @()
for ($index = 0; $index -lt $Samples; $index += 1) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $exePath -PassThru -WorkingDirectory $releaseRoot
    try {
        do {
            Start-Sleep -Milliseconds 25
            $process.Refresh()
        } while ([string]::IsNullOrWhiteSpace($process.MainWindowTitle) -and $watch.Elapsed.TotalSeconds -lt 10)
        $startupSamples += [math]::Round($watch.Elapsed.TotalMilliseconds, 1)
    }
    finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}

$idleProcess = Start-Process -FilePath $exePath -PassThru -WorkingDirectory $releaseRoot
Start-Sleep -Seconds 5
$idleProcess.Refresh()
$workingSetMB = [math]::Round($idleProcess.WorkingSet64 / 1MB, 1)
$privateMemoryMB = [math]::Round($idleProcess.PrivateMemorySize64 / 1MB, 1)
if (-not $idleProcess.HasExited) {
    Stop-Process -Id $idleProcess.Id -Force
}

$sorted = $startupSamples | Sort-Object
$median = $sorted[[int][math]::Floor($sorted.Count / 2)]
$packageBytes = Get-DirectorySize $releaseRoot

Write-Result @{
    scenario = "Flutter desktop app"
    status = "ok"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    samples = $Samples
    startupWindowReadyMs = $startupSamples
    medianStartupWindowReadyMs = $median
    idleWorkingSetMB = $workingSetMB
    idlePrivateMemoryMB = $privateMemoryMB
    packageDirectory = $releaseRoot
    packageBytes = $packageBytes
    packageMB = [math]::Round($packageBytes / 1MB, 2)
}
