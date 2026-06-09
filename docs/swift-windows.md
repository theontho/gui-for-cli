# Swift on Windows

Use this setup when validating the shared Swift core or CLI package from Windows.

## Install toolchain

Install the official Swift Windows toolchain with `winget`:

```powershell
winget install --id Swift.Toolchain --exact --accept-source-agreements --accept-package-agreements --silent
```

The Swift installer depends on Python 3.10 and the Visual C++ runtime. If `winget` stalls waiting for elevation while installing Python, install Python per-user first and then rerun the Swift install:

```powershell
$installer = Join-Path $env:TEMP "python-3.10.11-amd64.exe"
curl.exe -L "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" -o $installer
Start-Process -FilePath $installer -Wait -ArgumentList @(
  "/quiet",
  "/norestart",
  "InstallAllUsers=0",
  "PrependPath=1",
  "Include_launcher=0",
  "Include_test=0"
)
```

SwiftPM also needs MSVC `link.exe` and the Windows SDK. Install Visual Studio Build Tools with the C++ workload if `link.exe` is missing:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --accept-source-agreements --accept-package-agreements
```

## Shell environment

The Swift installer may not put every required directory on `PATH` for non-interactive shells. Before running SwiftPM, set the Swift, MSVC, Windows SDK, and Swift SDK paths in the same PowerShell session:

```powershell
$swiftRoot = "$env:LOCALAPPDATA\Programs\Swift"
$windowsKit = "C:\Program Files (x86)\Windows Kits\10"
$swiftPlatform = Get-ChildItem "$swiftRoot\Platforms" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$swiftToolchain = Get-ChildItem "$swiftRoot\Toolchains" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$swiftRuntime = Get-ChildItem "$swiftRoot\Runtimes" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$swiftPython = Get-ChildItem "$swiftRoot\Python-*" -Directory -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending |
  Select-Object -First 1
if (-not $swiftPython -and (Test-Path "$swiftRoot\Dependencies")) {
  $swiftPython = Get-ChildItem "$swiftRoot\Dependencies" -Directory | Sort-Object Name -Descending | Select-Object -First 1
}
$msvcRoot = @(
  "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
  "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$msvc = Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
$windowsKitVersion = Get-ChildItem "$windowsKit\Lib" -Directory | Sort-Object Name -Descending | Select-Object -First 1

$env:SDKROOT = "$($swiftPlatform.FullName)\Windows.platform\Developer\SDKs\Windows.sdk"
$env:Path = @(
  "$($swiftToolchain.FullName)\usr\bin",
  "$($swiftRuntime.FullName)\usr\bin",
  $(if ($swiftPython) { "$($swiftPython.FullName)\usr\bin" }),
  "$($msvc.FullName)\bin\Hostx64\x64",
  "$windowsKit\bin\$($windowsKitVersion.Name)\x64",
  "$windowsKit\bin\x64",
  $env:Path
) -join ";"
$env:INCLUDE = @(
  "$($msvc.FullName)\include",
  "$windowsKit\Include\$($windowsKitVersion.Name)\ucrt",
  "$windowsKit\Include\$($windowsKitVersion.Name)\shared",
  "$windowsKit\Include\$($windowsKitVersion.Name)\um",
  "$windowsKit\Include\$($windowsKitVersion.Name)\winrt",
  "$windowsKit\Include\$($windowsKitVersion.Name)\cppwinrt"
) -join ";"
$env:LIB = @(
  "$($msvc.FullName)\lib\x64",
  "$windowsKit\Lib\$($windowsKitVersion.Name)\ucrt\x64",
  "$windowsKit\Lib\$($windowsKitVersion.Name)\um\x64"
) -join ";"
```

Verify the toolchain:

```powershell
swift --version
```

## Validate core package

The repository platform runner currently skips `swift` tests on Windows because the main Swift platform target is macOS-oriented. Use SwiftPM directly for Windows validation:

```powershell
Set-Location platform\apple
swift build --target GUIForCLICoreTests
swift test --filter "decodesDemoJSONManifest|decodesBundleJSONComments|loadsPageFilesWithJSONComments" --no-parallel
```

Full `swift test` may still fail on older tests that assume POSIX script execution or executable permission bits. Those failures are Windows-portability gaps in the tests, not necessarily regressions in the shared core code being validated.
