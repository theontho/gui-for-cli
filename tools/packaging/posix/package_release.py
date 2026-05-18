#!/usr/bin/env python3
"""Build and stage POSIX release package layouts used by Makefile targets."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from embedded_branding import apple_embedded_branding  # noqa: E402
from common import REPO_ROOT, copy_path, make_executable, repo, reset_dir, run, run_tool  # noqa: E402
from macos_distribution import build_swift_distribution  # noqa: E402


def env_value(name: str, default: str) -> str:
    return os.environ.get(name) or default


RELEASE_DIR = Path(env_value("RELEASE_DIR", "out/release"))
APP_NAME = env_value("APP_NAME", "GUI for CLI")
APPKIT_APP_NAME = env_value("APPKIT_APP_NAME", "swift appkit test")
OBJC_APPKIT_APP_NAME = env_value("OBJC_APPKIT_APP_NAME", "GUI for CLI ObjC AppKit")
DERIVED_DATA_PATH = Path(env_value("DERIVED_DATA_PATH", "platform/apple/DerivedData"))
MACOS_DESTINATION = env_value("MACOS_DESTINATION", "platform=macOS")
GIO_GO = env_value("GIO_GO", "go")
FYNE_GO = env_value("FYNE_GO", "go")

APPLE_WORKSPACE = Path(env_value("APPLE_WORKSPACE", "platform/apple/GUIForCLI.xcworkspace"))
MACOS_RELEASE_APP = DERIVED_DATA_PATH / "Build/Products/Release" / f"{APP_NAME}.app"
MACOS_APPKIT_RELEASE_APP = DERIVED_DATA_PATH / "Build/Products/Release" / f"{APPKIT_APP_NAME}.app"
TAURI_BUNDLE_DIR = Path(
    os.environ.get(
        "TAURI_BUNDLE_DIR",
        "platform/typescript/web/packagers/tauri/target/release/bundle",
    )
)
FLUTTER_APP = Path(
    os.environ.get(
        "FLUTTER_APP",
        "exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app",
    )
)
RUST_APP_EXE = Path(
    os.environ.get(
        "RUST_APP_EXE",
        "exp-platform/rust/dioxus-shell/target/release/gui-for-cli-webui-dioxus",
    )
)
GTK4_EXE = Path(os.environ.get("GTK4_EXE", "exp-platform/rust/gtk4/target/release/gui-for-cli-gtk4"))
SLINT_EXE = Path(os.environ.get("SLINT_EXE", "exp-platform/rust/slint/target/release/gui-for-cli-slint"))
IMGUI_EXE = Path(os.environ.get("IMGUI_EXE", "exp-platform/rust/imgui/target/release/gui-for-cli-imgui"))
ICED_EXE = Path(os.environ.get("ICED_EXE", "exp-platform/rust/iced/target/release/gui-for-cli-iced"))
MAKEPAD_EXE = Path(os.environ.get("MAKEPAD_EXE", "exp-platform/rust/makepad/target/release/gui-for-cli-makepad"))
EGUI_EXE = Path(os.environ.get("EGUI_EXE", "exp-platform/rust/egui/target/release/gui-for-cli-egui"))
XILEM_VELLO_EXE = Path(
    os.environ.get(
        "XILEM_VELLO_EXE",
        "exp-platform/rust/xilem-vello/target/release/gui-for-cli-xilem-vello",
    )
)
GPUI_EXE = Path(os.environ.get("GPUI_EXE", "exp-platform/rust/gpui/target/release/gui-for-cli-gpui"))
IMGUI_CPP_EXE = Path(os.environ.get("IMGUI_CPP_EXE", "exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp"))
QT_QML_EXE = Path(os.environ.get("QT_QML_EXE", "exp-platform/cpp/qt-qml/build/gui-for-cli-qt-qml"))
RAYGUI_EXE = Path(os.environ.get("RAYGUI_EXE", "exp-platform/rust/raygui/target/release/gui-for-cli-raygui"))
RAYGUI_C_EXE = Path(os.environ.get("RAYGUI_C_EXE", "exp-platform/c/raygui/build/gui-for-cli-raygui-c"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=sorted(PACKAGES))
    args = parser.parse_args()
    PACKAGES[args.package]()
    return 0


def sync_apple_shared_resources() -> None:
    run(["python3", "tools/sync_apple_shared_resources.py"])


def release_path(name: str, default: str) -> Path:
    return repo(env_value(name, str(RELEASE_DIR / default)))


def copy_examples(dest: Path) -> None:
    copy_path("examples/WGSExtract", dest / "examples/WGSExtract")


def copy_resources(dest: Path) -> None:
    copy_path("resources", dest / "resources")


def copy_builtin_strings(dest: Path) -> None:
    copy_path(
        "platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings",
        dest / "platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings",
    )


def copy_web_assets(dest: Path) -> None:
    copy_path("platform/typescript/dist", dest / "platform/typescript/dist")
    copy_path("platform/typescript/web/vendor", dest / "platform/typescript/web/vendor")
    copy_path("platform/typescript/web/index.html", dest / "platform/typescript/web/index.html")
    copy_path("platform/typescript/web/styles.css", dest / "platform/typescript/web/styles.css")
    copy_path("platform/typescript/web/packagers/tauri/resources/node", dest / "node")


def stage_webui_payload(dest: Path) -> None:
    (dest / "platform/typescript/web").mkdir(parents=True, exist_ok=True)
    (dest / "examples").mkdir(parents=True, exist_ok=True)
    copy_web_assets(dest)
    copy_examples(dest)
    copy_resources(dest)


def stage_webui_release() -> None:
    run(["npm", "--prefix", "platform/typescript", "run", "build"])
    run(["npm", "--prefix", "platform/typescript", "run", "tauri:prepare-node"])
    dest = release_path("WEBUI_RELEASE_DIR", "webui")
    reset_dir(dest)
    stage_webui_payload(dest)
    launcher = dest / "run-webui.sh"
    launcher.write_text(
        "\n".join(
            [
                "#!/usr/bin/env sh",
                "set -eu",
                'cd "$(dirname "$0")"',
                'exec ./node/bin/node platform/typescript/dist/web/src/server/main.js --bundle "$(pwd)/examples/WGSExtract" "$@"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    make_executable(launcher)


def stage_swift_release() -> None:
    dest = release_path("SWIFT_RELEASE_DIR", "swiftui")
    reset_dir(dest)
    sync_apple_shared_resources()
    with apple_embedded_branding(REPO_ROOT) as branding:
        run(
            [
                "sh",
                "-c",
                f"cd {repo(APPLE_WORKSPACE).parent} && ../../scripts/tuist.sh clean manifests && ../../scripts/tuist.sh generate --no-open",
            ]
        )
        build_swift_distribution(
            repo_root=REPO_ROOT,
            workspace=repo(APPLE_WORKSPACE),
            scheme="GUIForCLIMac",
            derived_data_path=repo(DERIVED_DATA_PATH),
            destination=MACOS_DESTINATION,
            app_name=branding.effective_app_name or APP_NAME,
            output_dir=dest,
        )


def stage_appkit_release() -> None:
    sync_apple_shared_resources()
    run(
        [
            "xcodebuild",
            "-workspace",
            str(repo(APPLE_WORKSPACE)),
            "-scheme",
            "GUIForCLIAppKit",
            "-configuration",
            "Release",
            "-derivedDataPath",
            str(repo(DERIVED_DATA_PATH)),
            "-destination",
            MACOS_DESTINATION,
            "build",
            "CODE_SIGNING_ALLOWED=NO",
        ]
    )
    dest = release_path("APPKIT_RELEASE_DIR", "appkit")
    reset_dir(dest)
    copy_path(MACOS_APPKIT_RELEASE_APP, dest / f"{APPKIT_APP_NAME}.app")


def stage_webview_release() -> None:
    run(["npm", "--prefix", "platform/typescript", "run", "build"])
    run(["npm", "--prefix", "platform/typescript", "run", "tauri:prepare-node"])
    dest = release_path("WEBVIEW_RELEASE_DIR", "webview")
    app = dest / "GUI for CLI WebView Shell.app"
    resources = app / "Contents/Resources"
    reset_dir(dest)
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    copy_path("platform/typescript/web/packagers/webview-shell/Info.plist", app / "Contents/Info.plist")
    run(
        [
            "swiftc",
            "-O",
            "-framework",
            "AppKit",
            "-framework",
            "WebKit",
            "platform/typescript/web/packagers/webview-shell/Shell.swift",
            "-o",
            str(app / "Contents/MacOS/GUIForCLIWebViewShell"),
        ]
    )
    stage_webui_payload(resources)


def copy_matching_artifacts(bundle_dir: Path, dest: Path, patterns: list[str]) -> None:
    copied = False
    for pattern in patterns:
        for artifact in sorted(bundle_dir.glob(pattern)):
            copy_path(artifact, dest / artifact.name)
            copied = True
    if not copied:
        joined = ", ".join(patterns)
        raise FileNotFoundError(f"No artifacts matching [{joined}] under {bundle_dir}")



def stage_tauri_release() -> None:
    run(["npm", "--prefix", "platform/typescript", "run", "tauri:dist"])
    dest = release_path("TAURI_RELEASE_DIR", "tauri")
    reset_dir(dest)
    bundle_dir = repo(TAURI_BUNDLE_DIR)
    if sys.platform == "darwin":
        copy_matching_artifacts(bundle_dir, dest, ["macos/*.app", "dmg/*.dmg"])
    elif sys.platform.startswith("linux"):
        copy_matching_artifacts(bundle_dir, dest, ["deb/*.deb", "appimage/*.AppImage"])
    else:
        raise RuntimeError(f"Unsupported POSIX Tauri packaging platform: {sys.platform}")


def stage_dioxus_release() -> None:
    run(["npm", "--prefix", "platform/typescript", "run", "build"])
    run(["npm", "--prefix", "platform/typescript", "run", "tauri:prepare-node"])
    dest = release_path("DIOXUS_RELEASE_DIR", "dioxus")
    reset_dir(dest)
    stage_webui_payload(dest)
    copy_path(RUST_APP_EXE, dest / "gui-for-cli-webui-dioxus")
    make_executable(dest / "gui-for-cli-webui-dioxus")


def stage_electron_release() -> None:
    run(
        [
            "npm",
            "--prefix",
            "platform/typescript",
            "run",
            "electron:package",
            "--",
            "--out",
            str(release_path("ELECTRON_RELEASE_DIR", "electron").resolve()),
        ]
    )


def stage_gio_release() -> None:
    dest = release_path("GIO_RELEASE_DIR", "gio")
    reset_dir(dest)
    (dest / "examples").mkdir(parents=True, exist_ok=True)
    run_tool(
        GIO_GO,
        ["build", "-trimpath", "-ldflags=-s -w", "-o", str(dest / "gui-for-cli-gio"), "."],
        cwd=Path("exp-platform/go/gio"),
    )
    copy_examples(dest)
    copy_resources(dest)


def stage_avalonia_release() -> None:
    dest = release_path("AVALONIA_RELEASE_DIR", "avalonia")
    reset_dir(dest)
    run(
        [
            "dotnet",
            "publish",
            os.environ.get(
                "AVALONIA_APP_PROJECT",
                "exp-platform/dotnet/avalonia/GUIForCLIAvalonia/GUIForCLIAvalonia.csproj",
            ),
            "-c",
            "Release",
            "-o",
            str((dest / "app").resolve()),
        ]
    )
    copy_examples(dest)
    copy_resources(dest)


def stage_fyne_release() -> None:
    dest = release_path("FYNE_RELEASE_DIR", "fyne")
    reset_dir(dest)
    (dest / "examples").mkdir(parents=True, exist_ok=True)
    run_tool(
        FYNE_GO,
        ["build", "-trimpath", "-ldflags=-s -w", "-o", str(dest / "gui-for-cli-fyne"), "."],
        cwd=Path("exp-platform/go/fyne"),
    )
    copy_examples(dest)
    copy_resources(dest)


def stage_binary_release(
    release_env: str,
    default_dir: str,
    executable: Path,
    output_name: str,
    *,
    builtin_strings_only: bool = False,
) -> None:
    dest = release_path(release_env, default_dir)
    reset_dir(dest)
    copy_path(executable, dest / output_name)
    copy_examples(dest)
    if builtin_strings_only:
        copy_builtin_strings(dest)
    else:
        copy_resources(dest)


def stage_flutter_release() -> None:
    dest = release_path("FLUTTER_RELEASE_DIR", "flutter")
    reset_dir(dest)
    copy_path(FLUTTER_APP, dest / "GUI for CLI Flutter.app")


PACKAGES = {
    "appkit": stage_appkit_release,
    "avalonia": stage_avalonia_release,
    "dioxus": stage_dioxus_release,
    "egui": lambda: stage_binary_release("EGUI_RELEASE_DIR", "egui", EGUI_EXE, "gui-for-cli-egui"),
    "electron": stage_electron_release,
    "flutter": stage_flutter_release,
    "fyne": stage_fyne_release,
    "gio": stage_gio_release,
    "gpui": lambda: stage_binary_release("GPUI_RELEASE_DIR", "gpui", GPUI_EXE, "gui-for-cli-gpui"),
    "gtk4": lambda: stage_binary_release("GTK4_RELEASE_DIR", "gtk4", GTK4_EXE, "gui-for-cli-gtk4"),
    "iced": lambda: stage_binary_release(
        "ICED_RELEASE_DIR", "iced", ICED_EXE, "gui-for-cli-iced", builtin_strings_only=True
    ),
    "imgui": lambda: stage_binary_release("IMGUI_RELEASE_DIR", "imgui", IMGUI_EXE, "gui-for-cli-imgui"),
    "imgui-cpp": lambda: stage_binary_release(
        "IMGUI_CPP_RELEASE_DIR", "imgui-cpp", IMGUI_CPP_EXE, "gui-for-cli-imgui-cpp"
    ),
    "makepad": lambda: stage_binary_release(
        "MAKEPAD_RELEASE_DIR",
        "makepad",
        MAKEPAD_EXE,
        "gui-for-cli-makepad",
        builtin_strings_only=True,
    ),
    "qt-qml": lambda: stage_binary_release(
        "QT_QML_RELEASE_DIR", "qt-qml", QT_QML_EXE, "gui-for-cli-qt-qml"
    ),
    "raygui": lambda: stage_binary_release("RAYGUI_RELEASE_DIR", "raygui", RAYGUI_EXE, "gui-for-cli-raygui"),
    "raygui-c": lambda: stage_binary_release(
        "RAYGUI_C_RELEASE_DIR",
        "raygui-c",
        RAYGUI_C_EXE,
        "gui-for-cli-raygui-c",
        builtin_strings_only=True,
    ),
    "slint": lambda: stage_binary_release("SLINT_RELEASE_DIR", "slint", SLINT_EXE, "gui-for-cli-slint"),
    "swift": stage_swift_release,
    "tauri": stage_tauri_release,
    "webui": stage_webui_release,
    "webview": stage_webview_release,
    "xilem-vello": lambda: stage_binary_release(
        "XILEM_VELLO_RELEASE_DIR", "xilem-vello", XILEM_VELLO_EXE, "gui-for-cli-xilem-vello"
    ),
}


if __name__ == "__main__":
    raise SystemExit(main())
