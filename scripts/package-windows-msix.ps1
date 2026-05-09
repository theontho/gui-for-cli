param(
    [string]$DotNet = "dotnet",
    [string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$OutputDirectory = "out\windows-msix",
    [string]$CertificatePath = "",
    [string]$CertificatePassword = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $repoRoot "Apps\Windows\GUIForCLIWindows\GUIForCLIWindows.csproj"
$layoutSource = Join-Path $repoRoot "Apps\Windows\GUIForCLIWindows\bin\$Configuration\net10.0-windows10.0.19041.0\$RuntimeIdentifier"
$outputRoot = Join-Path $repoRoot $OutputDirectory
$layout = Join-Path $outputRoot "layout"
$package = Join-Path $outputRoot "GUIForCLIWindows-$RuntimeIdentifier.msix"

& $DotNet publish $project -c $Configuration -p:RuntimeIdentifier=$RuntimeIdentifier -p:WindowsAppSDKSelfContained=true -p:SelfContained=true /nr:false
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force $outputRoot | Out-Null
if (Test-Path $layout) {
    Remove-Item $layout -Recurse -Force
}
New-Item -ItemType Directory -Force $layout | Out-Null

Get-ChildItem $layoutSource -Force | Where-Object { $_.Name -ne "publish" } | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $layout $_.Name) -Recurse -Force
}

$makeAppx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($makeAppx)) {
    throw "makeappx.exe was not found. Install the Windows SDK packaging tools."
}

if (Test-Path $package) {
    Remove-Item $package -Force
}
& $makeAppx pack /d $layout /p $package /overwrite
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
    $signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ([string]::IsNullOrWhiteSpace($signtool)) {
        throw "signtool.exe was not found. Install the Windows SDK signing tools."
    }

    $signArgs = @("sign", "/fd", "SHA256", "/f", $CertificatePath)
    if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
        $signArgs += @("/p", $CertificatePassword)
    }
    $signArgs += $package
    & $signtool @signArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Output $package
