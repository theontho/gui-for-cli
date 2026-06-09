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
$msvc = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.43.34808"
$windowsKit = "C:\Program Files (x86)\Windows Kits\10"
$windowsKitVersion = "10.0.20348.0"

$env:SDKROOT = "$swiftRoot\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
$env:Path = @(
  "$swiftRoot\Toolchains\6.3.2+Asserts\usr\bin",
  "$swiftRoot\Runtimes\6.3.2\usr\bin",
  "$swiftRoot\Python-3.10.1\usr\bin",
  "$msvc\bin\Hostx64\x64",
  "$windowsKit\bin\$windowsKitVersion\x64",
  "$windowsKit\bin\x64",
  $env:Path
) -join ";"
$env:INCLUDE = @(
  "$msvc\include",
  "$windowsKit\Include\$windowsKitVersion\ucrt",
  "$windowsKit\Include\$windowsKitVersion\shared",
  "$windowsKit\Include\$windowsKitVersion\um",
  "$windowsKit\Include\$windowsKitVersion\winrt",
  "$windowsKit\Include\$windowsKitVersion\cppwinrt"
) -join ";"
$env:LIB = @(
  "$msvc\lib\x64",
  "$windowsKit\Lib\$windowsKitVersion\ucrt\x64",
  "$windowsKit\Lib\$windowsKitVersion\um\x64"
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
