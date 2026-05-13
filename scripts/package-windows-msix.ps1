param(
    [string]$DotNet = "dotnet",
    [string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$OutputDirectory = "out\windows-msix",
    [string]$CertificatePath = "",
    [securestring]$CertificatePassword = (New-Object securestring)
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Join-Path $repoRoot "exp-platform\windows\dotnet\GUIForCLIWindows\GUIForCLIWindows.csproj"
$layoutSource = Join-Path $repoRoot "exp-platform\windows\dotnet\GUIForCLIWindows\bin\$Configuration\net10.0-windows10.0.19041.0\$RuntimeIdentifier"
$publishSource = Join-Path $layoutSource "publish"
$outputRoot = Join-Path $repoRoot $OutputDirectory
$layout = Join-Path $outputRoot "layout"
$package = Join-Path $outputRoot "GUIForCLIWindows-$RuntimeIdentifier.msix"
$platform = switch ($RuntimeIdentifier) {
    "win-x86" { "x86" }
    "win-x64" { "x64" }
    "win-arm64" { "ARM64" }
    default { throw "Unsupported RuntimeIdentifier '$RuntimeIdentifier'. Expected win-x86, win-x64, or win-arm64." }
}

& $DotNet publish $project -c $Configuration -p:Platform=$platform -p:RuntimeIdentifier=$RuntimeIdentifier -p:WindowsAppSDKSelfContained=true -p:SelfContained=true /nr:false
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $publishSource -PathType Container)) {
    throw "Publish output was not found: $publishSource"
}

New-Item -ItemType Directory -Force $outputRoot | Out-Null
if (Test-Path $layout) {
    Remove-Item $layout -Recurse -Force
}
New-Item -ItemType Directory -Force $layout | Out-Null

Get-ChildItem $publishSource -Force | ForEach-Object {
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
    $plainPassword = ""
    $passwordHandle = [IntPtr]::Zero
    try {
        $passwordHandle = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertificatePassword)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordHandle)
        if (-not [string]::IsNullOrWhiteSpace($plainPassword)) {
            $signArgs += @("/p", $plainPassword)
        }
    } finally {
        if ($passwordHandle -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordHandle)
        }
    }
    $signArgs += $package
    & $signtool @signArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Output $package
