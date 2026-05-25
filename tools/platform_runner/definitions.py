"""Shared platform runner definitions."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .core import Operation, REPO_ROOT, Step, sh
from tools.devconfig import get_path

sys.path.insert(0, str(REPO_ROOT / "tools/benchmarking"))
from benchmark_catalog import (  # noqa: E402
    COMMANDS as BENCHMARK_COMMANDS,
    SCREENSHOT_ORDER,
    SCREENSHOT_SUITES,
    SUITES as BENCHMARK_SUITES,
)


def env_or_default(name: str, default: str) -> str:
    return os.environ.get(name) or default


APPLE_DIR = "platform/apple"
APPLE_WORKSPACE = f"{APPLE_DIR}/GUIForCLI.xcworkspace"
DERIVED_DATA_PATH = os.environ.get("DERIVED_DATA_PATH", f"{APPLE_DIR}/DerivedData")
APPLE_PLATFORMS = ("darwin",)


def default_embedded_app_name() -> str:
    configured_name = (
        os.environ.get("PACKAGE_APP_NAME")
        or os.environ.get("EMBEDDED_APP_NAME")
        or get_path("packaging", "app_name", default="")
    )
    if configured_name:
        return str(configured_name)
    bundle_path = (
        os.environ.get("EMBEDDED_BUNDLE_PATH")
        or os.environ.get("PACKAGE_BUNDLE_PATH")
        or get_path("packaging", "embedded_bundle_path", default="")
        or "examples/WGSExtract"
    )
    return Path(str(bundle_path)).name or "GUI for CLI"


APP_NAME = env_or_default("APP_NAME", default_embedded_app_name())
APPKIT_APP_NAME = os.environ.get("APPKIT_APP_NAME", "swift appkit test")
OBJC_APPKIT_APP_NAME = os.environ.get("OBJC_APPKIT_APP_NAME", "GUI for CLI ObjC AppKit Test")
IOS_BUNDLE_ID = os.environ.get("IOS_BUNDLE_ID", "dev.guiforcli.gui-for-cli.ios")
IOS_CORE_RESOURCE_BUNDLE = os.environ.get(
    "IOS_CORE_RESOURCE_BUNDLE", "GUIForCLIShared_GUIForCLICore.bundle"
)
IOS_SIM_DESTINATION = env_or_default("IOS_SIM_DESTINATION", "generic/platform=iOS Simulator")
IOS_DEVICE_DESTINATION = env_or_default("IOS_DEVICE_DESTINATION", "generic/platform=iOS")
MACOS_DESTINATION = env_or_default("MACOS_DESTINATION", "platform=macOS")
DEFAULT_BUNDLE = os.environ.get("DEFAULT_BUNDLE") or "examples/WGSExtract"
BUNDLE_ROOT = Path(os.environ.get("BUNDLE") or DEFAULT_BUNDLE).resolve()
WEB_PORT = os.environ.get("PORT") or "8787"
RELEASE_DIR = os.environ.get("RELEASE_DIR") or "out/release"
PYTHON = os.environ.get("PYTHON") or ("python" if sys.platform.startswith("win") else "uv run python")
APPLE_RESOURCE_SYNC = f"python3 {sh('tools/sync_apple_shared_resources.py')}"
LOCAL_DOTNET = REPO_ROOT / ".dotnet-sdk" / "dotnet.exe"
DOTNET = os.environ.get("DOTNET") or (str(LOCAL_DOTNET) if LOCAL_DOTNET.exists() else "dotnet")
DOTNET_BUILD_FLAGS = "--disable-build-servers /nr:false -p:UseSharedCompilation=false"
CONFIGURATION = os.environ.get("CONFIGURATION", "Debug")
RUNTIME_IDENTIFIER = os.environ.get("RUNTIME_IDENTIFIER", "win-x64")
BENCHMARK_EXECUTABLE = os.environ.get("BENCHMARK_EXECUTABLE", "")
BENCHMARK_ITERATIONS = os.environ.get("BENCHMARK_ITERATIONS", "7")
CERT = os.environ.get("CERT", "")
CERT_PASSWORD = os.environ.get("CERT_PASSWORD", "")
TEXTUAL_PYTHON = os.environ.get("TEXTUAL_PYTHON", PYTHON)
PYTHON_PIP_ENV = os.environ.get("PYTHON_PIP_ENV", "")
GIO_GO = os.environ.get("GIO_GO", "GOTOOLCHAIN=go1.25.0 go")
FYNE_GO = os.environ.get("FYNE_GO", "GOTOOLCHAIN=go1.25.0 go")
KOTLIN_COMPOSE_DIR = "exp-platform/kotlin/compose"
KOTLIN_GRADLE = os.environ.get("KOTLIN_GRADLE", "gradle")
KOTLIN_GRADLE_FLAGS = os.environ.get("KOTLIN_GRADLE_FLAGS", "--console=plain --quiet")
KOTLIN_JAVA_HOME = os.environ.get(
    "KOTLIN_JAVA_HOME",
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    if Path("/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home").exists()
    else "",
)
KOTLIN_ANDROID_HOME = os.environ.get(
    "KOTLIN_ANDROID_HOME",
    str(Path.home() / "Library/Android/sdk") if (Path.home() / "Library/Android/sdk").exists() else "",
)

MACOS_APP = f"{DERIVED_DATA_PATH}/Build/Products/Debug/{APP_NAME}.app"
MACOS_APPKIT_APP = f"{DERIVED_DATA_PATH}/Build/Products/Debug/{APPKIT_APP_NAME}.app"
OBJC_APPKIT_APP = f"{DERIVED_DATA_PATH}/Build/Products/Debug/{OBJC_APPKIT_APP_NAME}.app"
OBJC_APPKIT_EXE = f"{OBJC_APPKIT_APP}/Contents/MacOS/{OBJC_APPKIT_APP_NAME}"
OBJC_APPKIT_RELEASE_APP = f"{DERIVED_DATA_PATH}/Build/Products/Release/{OBJC_APPKIT_APP_NAME}.app"
IOS_SIM_APP = f"{DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/{APP_NAME}.app"
IOS_DEVICE_APP = f"{DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/{APP_NAME}.app"
IOS_SIM_DEMO_BUNDLE = f"{IOS_SIM_APP}/{IOS_CORE_RESOURCE_BUNDLE}/Resources/DemoBundles/WGSExtract"
IOS_DEVICE_DEMO_BUNDLE = f"{IOS_DEVICE_APP}/{IOS_CORE_RESOURCE_BUNDLE}/Resources/DemoBundles/WGSExtract"
WEBVIEW_SHELL_APP = f"{DERIVED_DATA_PATH}/WebViewShell/GUI for CLI WebView Shell.app"
WEBVIEW_SHELL_EXE = f"{WEBVIEW_SHELL_APP}/Contents/MacOS/GUIForCLIWebViewShell"
RUST_APPS_DIR = "exp-platform/rust/dioxus-shell"
TYPESCRIPT_DIR = "platform/typescript"
RUST_APP_EXE = f"{RUST_APPS_DIR}/target/release/gui-for-cli-webui-dioxus"
GTK4_EXE = "exp-platform/rust/gtk4/target/release/gui-for-cli-gtk4"
SLINT_EXE = "exp-platform/rust/slint/target/release/gui-for-cli-slint"
RAYGUI_EXE = "exp-platform/rust/raygui/target/release/gui-for-cli-raygui"
RAYGUI_C_BUILD_DIR = "exp-platform/c/raygui/build"
RAYGUI_C_EXE = f"{RAYGUI_C_BUILD_DIR}/gui-for-cli-raygui-c"
IMGUI_EXE = "exp-platform/rust/imgui/target/release/gui-for-cli-imgui"
ICED_EXE = "exp-platform/rust/iced/target/release/gui-for-cli-iced"
MAKEPAD_EXE = "exp-platform/rust/makepad/target/release/gui-for-cli-makepad"
EGUI_EXE = "exp-platform/rust/egui/target/release/gui-for-cli-egui"
XILEM_VELLO_EXE = "exp-platform/rust/xilem-vello/target/release/gui-for-cli-xilem-vello"
GPUI_EXE = "exp-platform/rust/gpui/target/release/gui-for-cli-gpui"
MOJO_DIR = "exp-platform/mojo"
MOJO_EXE = "out/mojo/gui-for-cli-mojo"
IMGUI_CPP_BUILD_DIR = "exp-platform/cpp/imgui-cpp/build"
IMGUI_CPP_EXE = f"{IMGUI_CPP_BUILD_DIR}/gui-for-cli-imgui-cpp"
QT_QML_BUILD_DIR = "exp-platform/cpp/qt-qml/build"
QT_QML_VALIDATE_BUILD_DIR = "exp-platform/cpp/qt-qml/build-validate"
QT_QML_EXE = f"{QT_QML_BUILD_DIR}/gui-for-cli-qt-qml"
AVALONIA_DIR = "exp-platform/dotnet/avalonia"
AVALONIA_APP_PROJECT = f"{AVALONIA_DIR}/GUIForCLIAvalonia/GUIForCLIAvalonia.csproj"
AVALONIA_TEST_PROJECT = f"{AVALONIA_DIR}/GUIForCLIAvalonia.Tests/GUIForCLIAvalonia.Tests.csproj"
WINDOWS_DIR = "exp-platform/windows"
WINDOWS_SLN = f"{WINDOWS_DIR}/GUIForCLIWindows.sln"
WINDOWS_APP_PROJECT = f"{WINDOWS_DIR}/dotnet/GUIForCLIWindows/GUIForCLIWindows.csproj"
WINDOWS_CORE_PROJECT = f"{WINDOWS_DIR}/dotnet/GUIForCLIWindows.Core/GUIForCLIWindows.Core.csproj"
WINDOWS_CORE_TEST_PROJECT = f"{WINDOWS_DIR}/dotnet/GUIForCLIWindows.CoreTests/GUIForCLIWindows.CoreTests.csproj"
PYTHON_SHARED_DIR = "exp-platform/python/shared"
TEXTUAL_DIR = "exp-platform/python/textual"
TKINTER_DIR = "exp-platform/python/tkinter"
WX_DIR = "exp-platform/python/wx"
PYTHON_TOGA_DIR = "exp-platform/python/toga"
PYTHON_TOGA_SRC = f"{PYTHON_TOGA_DIR}/src"
PYTHON_TOGA_WORKSPACE = os.environ.get("PYTHON_TOGA_WORKSPACE", "tmp/python-toga-workspace")
PYTHON_RENDERER_PATH = os.pathsep.join((PYTHON_SHARED_DIR, TEXTUAL_DIR, TKINTER_DIR, WX_DIR))
PYTHON_WITH_TOGA_PATH = os.pathsep.join((PYTHON_RENDERER_PATH, str(Path(PYTHON_TOGA_SRC).resolve())))
SWIFT_FORMAT_PATHS = " ".join(
    sh(path)
    for path in (
        f"{APPLE_DIR}/Package.swift",
        f"{APPLE_DIR}/Project.swift",
        f"{APPLE_DIR}/Tuist.swift",
        f"{APPLE_DIR}/shared/Package.swift",
        f"{APPLE_DIR}/shared/Sources",
        f"{APPLE_DIR}/shared/Tests",
        f"{APPLE_DIR}/shared/app",
        f"{APPLE_DIR}/swiftui",
        f"{APPLE_DIR}/exp",
        "scripts",
    )
)
FLUTTER_WINDOW_WIDTH = os.environ.get("FLUTTER_WINDOW_WIDTH", "1344")
FLUTTER_WINDOW_HEIGHT = os.environ.get("FLUTTER_WINDOW_HEIGHT", "864")
FLUTTER_CONFIGURE_WINDOW = (
    f"{PYTHON} ../../../tools/experiments/configure_flutter_macos_window.py "
    f"macos/Runner/MainFlutterWindow.swift --width {sh(FLUTTER_WINDOW_WIDTH)} "
    f"--height {sh(FLUTTER_WINDOW_HEIGHT)}"
)
FLUTTER_SETUP = (
    "flutter create --empty --platforms=macos --project-name gui_for_cli_flutter . && "
    "/usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' "
    "macos/Runner/DebugProfile.entitlements && "
    "/usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' "
    "macos/Runner/Release.entitlements && "
    f"{FLUTTER_CONFIGURE_WINDOW} && "
    "rm -f README.md analysis_options.yaml *.iml test/widget_test.dart"
)


def cmd(
    command: str,
    *,
    cwd: str | None = None,
    env: dict[str, str] | None = None,
    platforms: tuple[str, ...] = (),
    windows_command: str | None = None,
) -> Step:
    return Step(
        command=command,
        cwd=Path(cwd) if cwd else None,
        env=env or {},
        platforms=platforms,
        windows_command=windows_command,
    )


def op(
    *steps: Step,
    deps: tuple[tuple[str, str], ...] = (),
    description: str = "",
) -> Operation:
    return Operation(steps=tuple(steps), dependencies=deps, description=description)


def swift_env(command: str) -> str:
    return f"GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all {command}"


def project() -> tuple[tuple[str, str], ...]:
    return (("setup", "apple-project"),)


def xcodebuild(scheme: str, configuration: str, destination: str) -> str:
    return (
        f"xcodebuild -workspace {sh(APPLE_WORKSPACE)} -scheme {sh(scheme)} "
        f"-configuration {sh(configuration)} -derivedDataPath {sh(DERIVED_DATA_PATH)} "
        f"-destination {sh(destination)} build CODE_SIGNING_ALLOWED=NO"
    )


def materialize_ios_resources(app: str, demo_bundle: str) -> str:
    return (
        f"if [ -L {sh(demo_bundle)} ]; then "
        "echo 'Materializing WGSExtract demo bundle for iOS install'; "
        f"rm {sh(demo_bundle)}; ditto examples/WGSExtract {sh(demo_bundle)}; fi; "
        "for resource in BuiltinStrings BuiltinIconMap; do "
        f"path={sh(app)}/{sh(IOS_CORE_RESOURCE_BUNDLE)}/Resources/$resource; "
        "if [ -L \"$path\" ]; then echo \"Materializing $resource for iOS install\"; "
        "rm \"$path\"; ditto \"resources/$resource\" \"$path\"; fi; done"
    )


def ios_sim_run(simulator_env: str, device_filter: str = "iPhone|iPad") -> str:
    return (
        "set -eu; "
        f"simulator=\"${{{simulator_env}:-booted}}\"; "
        "if [ \"$simulator\" = booted ]; then "
        "simulator=\"$(xcrun simctl list devices booted | "
        "sed -nE 's/.*\\(([0-9A-F-]{36})\\) \\(Booted\\).*/\\1/p' | head -n 1)\"; "
        "if [ -z \"$simulator\" ]; then "
        f"simulator=\"$(xcrun simctl list devices available | sed -nE '/{device_filter}/s/.*\\(([0-9A-F-]{{36}})\\) \\(Shutdown\\).*/\\1/p' | head -n 1)\"; "
        "if [ -z \"$simulator\" ]; then echo 'No booted or available iOS simulators found.' >&2; exit 1; fi; "
        "echo \"No simulator is booted; booting $simulator\"; xcrun simctl boot \"$simulator\" || true; fi; "
        "else xcrun simctl boot \"$simulator\" || true; fi; "
        "xcrun simctl bootstatus \"$simulator\" -b; "
        "simulator_udid=\"$(xcrun simctl getenv \"$simulator\" SIMULATOR_UDID 2>/dev/null || printf '%s' \"$simulator\")\"; "
        "open -a Simulator --args -CurrentDeviceUDID \"$simulator_udid\"; "
        f"xcrun simctl install \"$simulator_udid\" {sh(IOS_SIM_APP)}; "
        f"xcrun simctl launch \"$simulator_udid\" {sh(IOS_BUNDLE_ID)}"
    )


def kotlin_env_prefix() -> str:
    pieces: list[str] = []
    if KOTLIN_JAVA_HOME:
        pieces.append(f"JAVA_HOME={sh(KOTLIN_JAVA_HOME)}")
    if KOTLIN_ANDROID_HOME:
        pieces.append(f"ANDROID_HOME={sh(KOTLIN_ANDROID_HOME)} ANDROID_SDK_ROOT={sh(KOTLIN_ANDROID_HOME)}")
    return " ".join(pieces)


KOTLIN_PREFIX = kotlin_env_prefix()


def ps(command: str) -> str:
    escaped = command.replace('"', '\\"')
    return f'pwsh -NoProfile -ExecutionPolicy Bypass -Command "{escaped}"'


def ps_file(path: str, *arguments: str) -> str:
    args = " ".join(arguments)
    return f"pwsh -NoProfile -ExecutionPolicy Bypass -File {win(path)}{(' ' + args) if args else ''}"


def win(value: str | Path) -> str:
    text = str(value)
    if not text or any(character.isspace() for character in text):
        escaped = text.replace('"', '\\"')
        return f'"{escaped}"'
    return text


def windows_platform(runtime_identifier: str = RUNTIME_IDENTIFIER) -> str:
    return {
        "win-x86": "x86",
        "win-x64": "x64",
        "win-arm64": "ARM64",
    }.get(runtime_identifier, "x64")


def windows_publish(output_directory: str, *, ready_to_run: bool = False, native_aot: bool = False) -> str:
    args = [
        win(DOTNET),
        "publish",
        win(WINDOWS_APP_PROJECT),
        "-c Release",
        f"-o {win(output_directory)}",
        f"-p:Platform={windows_platform()}",
        f"-p:RuntimeIdentifier={win(RUNTIME_IDENTIFIER)}",
        "-p:WindowsAppSDKSelfContained=true",
        "-p:SelfContained=true",
        "-p:UseSharedCompilation=false",
    ]
    if ready_to_run:
        args.append("-p:PublishReadyToRun=true")
    if native_aot:
        args.extend(("-p:PublishAot=true", "-p:PublishTrimmed=true"))
    args.append("/nr:false")
    return " ".join(args)
