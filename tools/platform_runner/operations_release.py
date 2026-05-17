"""Package, release-build, clean, benchmark, and screenshot operations."""

from __future__ import annotations

from .definitions import *  # noqa: F403


PACKAGE_TARGETS = (
    "webui",
    "swift",
    "appkit",
    "webview",
    "tauri",
    "dioxus",
    "electron",
    "gio",
    "avalonia",
    "fyne",
    "gtk4",
    "slint",
    "imgui",
    "iced",
    "makepad",
    "egui",
    "xilem-vello",
    "gpui",
    "imgui-cpp",
    "qt-qml",
    "raygui",
    "raygui-c",
    "flutter",
    "windows-msix",
    "windows-bootstrap",
)

DEFAULT_WINDOWS_BENCHMARK_EXECUTABLE = "out\\windows-publish\\GUIForCLIWindows.exe"
WINDOWS_PACKAGE_COMMANDS = {
    "webui": ps_file("tools/packaging/windows/package_webui.ps1"),
    "tauri": ps_file("tools/packaging/windows/package_tauri.ps1"),
    "electron": ps(
        "Push-Location platform\\typescript; "
        "npm run electron:package -- --out ..\\..\\out\\windows-electron --platform win32 --arch x64; "
        "$status=$LASTEXITCODE; Pop-Location; exit $status"
    ),
    "dioxus": ps_file("tools/packaging/windows/package_dioxus.ps1"),
    "gio": ps_file("tools/packaging/windows/package_gio.ps1"),
    "slint": ps_file(
        "tools/packaging/windows/package_binary.ps1",
        "-ManifestPath exp-platform\\rust\\slint\\Cargo.toml",
        "-ExecutablePath exp-platform\\rust\\slint\\target\\release\\gui-for-cli-slint.exe",
        "-OutputDirectory out\\windows-slint",
        "-ZipName GUIForCLISlint-win-x64.zip",
    ),
    "imgui": ps_file(
        "tools/packaging/windows/package_binary.ps1",
        "-ManifestPath exp-platform\\rust\\imgui\\Cargo.toml",
        "-ExecutablePath exp-platform\\rust\\imgui\\target\\release\\gui-for-cli-imgui.exe",
        "-OutputDirectory out\\windows-imgui",
        "-ZipName GUIForCLIImGui-win-x64.zip",
    ),
    "windows-msix": ps_file(
        "tools/packaging/windows/package_msix.ps1",
        f"-DotNet {win(DOTNET)}",
        f"-Configuration {win(CONFIGURATION)}",
        f"-RuntimeIdentifier {win(RUNTIME_IDENTIFIER)}",
    ),
    "windows-bootstrap": ps_file(
        "tools/packaging/windows/package_bootstrap.ps1",
        f"-DotNet {win(DOTNET)}",
        f"-Configuration {win(CONFIGURATION)}",
        f"-RuntimeIdentifier {win(RUNTIME_IDENTIFIER)}",
    ),
}


def package_operation(target: str) -> Operation:
    windows_command = WINDOWS_PACKAGE_COMMANDS.get(target, "")
    posix_command = f"{PYTHON} tools/packaging/posix/package_release.py {sh(target)}"
    if target.startswith("windows-"):
        return op(cmd(windows_command, platforms=("windows",)))
    return op(
        cmd(
            posix_command,
            platforms=("darwin", "linux") if not windows_command else (),
            windows_command=windows_command or None,
        )
    )


PACKAGE: dict[str, Operation] = {target: package_operation(target) for target in PACKAGE_TARGETS}

RELEASE_BUILD: dict[str, Operation] = {target: package_operation(target) for target in PACKAGE_TARGETS}
RELEASE_BUILD["windows"] = op(cmd(windows_publish("out\\windows-publish"), platforms=("windows",)))
RELEASE_BUILD["windows-readytorun"] = op(
    cmd(windows_publish("out\\windows-publish-readytorun", ready_to_run=True), platforms=("windows",))
)
RELEASE_BUILD["windows-nativeaot"] = op(
    cmd(windows_publish("out\\windows-publish-nativeaot", native_aot=True), platforms=("windows",))
)
RELEASE_BUILD["objc-appkit-macos"] = op(
    cmd(xcodebuild("GUIForCLIObjCAppKit", "Release", MACOS_DESTINATION), platforms=("darwin",)),
    deps=project(),
)

CLEAN: dict[str, Operation] = {
    "all": op(
        cmd(swift_env(f"swift package --package-path {sh(APPLE_DIR)} clean")),
        cmd(
            f"rm -rf {sh(APPLE_DIR + '/GUIForCLI.xcodeproj')} {sh(APPLE_WORKSPACE)} "
            f"{sh(APPLE_DIR + '/Derived')} {sh(DERIVED_DATA_PATH)} "
            f"{sh(APPLE_DIR + '/.build')} {sh(APPLE_DIR + '/.swiftpm')} "
            "exp-platform/rust/raygui/target exp-platform/c/raygui/build "
            "exp-platform/rust/makepad/target out/* tmp/*"
        ),
    )
}

BENCHMARK: dict[str, Operation] = {
    name: op(cmd(f"{PYTHON} tools/benchmarking/benchmark.py benchmark {sh(name)}"))
    for name in sorted(set(BENCHMARK_COMMANDS) | set(BENCHMARK_SUITES))
}
BENCHMARK["windows"] = op(
    cmd(
        ps_file(
            "tools/benchmarking/benchmark_windows_app.ps1",
            f"-Executable {win(BENCHMARK_EXECUTABLE or DEFAULT_WINDOWS_BENCHMARK_EXECUTABLE)}",
            f"-Iterations {win(BENCHMARK_ITERATIONS)}",
        ),
        platforms=("windows",),
    )
)
BENCHMARK["flutter-windows"] = op(
    cmd(ps_file("tools/benchmarking/benchmark_flutter.ps1"), platforms=("windows",))
)
BENCHMARK["slint"] = op(
    cmd(
        f"{PYTHON} tools/benchmarking/benchmark.py benchmark slint",
        windows_command=ps(
            "cargo build --manifest-path exp-platform/rust/slint/Cargo.toml --release; "
            "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; "
            "$previousOffline=$env:GUI_FOR_CLI_OFFLINE; "
            "$env:GUI_FOR_CLI_OFFLINE='1'; "
            "$bundle = if ($env:BUNDLE) { (Resolve-Path $env:BUNDLE).Path } else { (Resolve-Path examples/WGSExtract).Path }; "
            "try { exp-platform/rust/slint/target/release/gui-for-cli-slint.exe "
            "--bundle $bundle --benchmark --benchmark-full --once } "
            "finally { $env:GUI_FOR_CLI_OFFLINE=$previousOffline }"
        ),
    )
)
BENCHMARK["imgui"] = op(
    cmd(
        f"{PYTHON} tools/benchmarking/benchmark.py benchmark imgui",
        windows_command=ps(
            "cargo build --manifest-path exp-platform/rust/imgui/Cargo.toml --release; "
            "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; "
            "$previousOffline=$env:GUI_FOR_CLI_OFFLINE; "
            "$env:GUI_FOR_CLI_OFFLINE='1'; "
            "$bundle = if ($env:BUNDLE) { (Resolve-Path $env:BUNDLE).Path } else { (Resolve-Path examples/WGSExtract).Path }; "
            "try { exp-platform/rust/imgui/target/release/gui-for-cli-imgui.exe "
            "--bundle $bundle --benchmark --benchmark-full --once } "
            "finally { $env:GUI_FOR_CLI_OFFLINE=$previousOffline }"
        ),
    )
)
BENCHMARK["list"] = op(cmd(f"{PYTHON} tools/benchmarking/benchmark.py list"))

SCREENSHOT: dict[str, Operation] = {
    name: op(cmd(f"{PYTHON} tools/benchmarking/benchmark.py screenshot {sh(name)}"))
    for name in sorted(set(SCREENSHOT_MAP) | set(SCREENSHOT_ORDER) | set(SCREENSHOT_SUITES))
}
