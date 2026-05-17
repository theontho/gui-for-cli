"""Build and run operations."""

from __future__ import annotations

from .definitions import *  # noqa: F403


BUILD: dict[str, Operation] = {
    "cli": op(cmd(swift_env(f"swift build --package-path {sh(APPLE_DIR)} -c release"))),
    "webui": op(cmd("npm run build", cwd=TYPESCRIPT_DIR)),
    "webview-shell": op(
        cmd("npm run build", cwd=TYPESCRIPT_DIR),
        cmd(f"rm -rf {sh(WEBVIEW_SHELL_APP)} && mkdir -p {sh(WEBVIEW_SHELL_APP + '/Contents/MacOS')} {sh(WEBVIEW_SHELL_APP + '/Contents/Resources')}"),
        cmd(f"cp platform/typescript/web/packagers/webview-shell/Info.plist {sh(WEBVIEW_SHELL_APP + '/Contents/Info.plist')}"),
        cmd(
            "swiftc -O -framework AppKit -framework WebKit "
            f"platform/typescript/web/packagers/webview-shell/Shell.swift -o {sh(WEBVIEW_SHELL_EXE)}"
        ),
    ),
    "tauri": op(cmd("npm run tauri:build", cwd=TYPESCRIPT_DIR)),
    "dioxus": op(
        cmd("npm run build", cwd=TYPESCRIPT_DIR),
        cmd(f"cargo build --release --manifest-path {sh(RUST_APPS_DIR + '/Cargo.toml')}"),
    ),
    "gtk4": op(cmd("cargo build --manifest-path exp-platform/rust/gtk4/Cargo.toml --features gtk-ui --release")),
    "slint": op(cmd("cargo build --manifest-path exp-platform/rust/slint/Cargo.toml --release")),
    "raygui": op(cmd("cargo build --manifest-path exp-platform/rust/raygui/Cargo.toml --release")),
    "raygui-c": op(
        cmd(f"cmake -S exp-platform/c/raygui -B {sh(RAYGUI_C_BUILD_DIR)} -DCMAKE_BUILD_TYPE=Release"),
        cmd(f"cmake --build {sh(RAYGUI_C_BUILD_DIR)} --config Release"),
    ),
    "imgui": op(cmd("cargo build --manifest-path exp-platform/rust/imgui/Cargo.toml --release")),
    "iced": op(cmd("cargo build --manifest-path exp-platform/rust/iced/Cargo.toml --release")),
    "makepad": op(cmd("cargo build --manifest-path exp-platform/rust/makepad/Cargo.toml --release")),
    "egui": op(cmd("cargo build --manifest-path exp-platform/rust/egui/Cargo.toml --release")),
    "xilem-vello": op(cmd("cargo build --manifest-path exp-platform/rust/xilem-vello/Cargo.toml --release")),
    "gpui": op(cmd("cargo build --manifest-path exp-platform/rust/gpui/Cargo.toml --release")),
    "mojo": op(cmd(f"mkdir -p {sh(str(Path(MOJO_EXE).parent))}"), cmd(f"pixi run mojo build src/gui_for_cli_mojo.mojo -o ../../{MOJO_EXE}", cwd=MOJO_DIR)),
    "imgui-cpp": op(
        cmd(f"cmake -S exp-platform/cpp/imgui-cpp -B {sh(IMGUI_CPP_BUILD_DIR)} -DCMAKE_BUILD_TYPE=Release"),
        cmd(f"cmake --build {sh(IMGUI_CPP_BUILD_DIR)} --config Release"),
    ),
    "qt-qml": op(
        cmd(f"cmake -S exp-platform/cpp/qt-qml -B {sh(QT_QML_BUILD_DIR)} -DCMAKE_BUILD_TYPE=Release"),
        cmd(f"cmake --build {sh(QT_QML_BUILD_DIR)} --config Release"),
    ),
    "avalonia": op(
        cmd(f"dotnet restore {sh(AVALONIA_TEST_PROJECT)}"),
        cmd(f"dotnet build {sh(AVALONIA_APP_PROJECT)} --no-restore"),
    ),
    "windows-core": op(cmd(f"{DOTNET} build {sh(WINDOWS_CORE_PROJECT)} {DOTNET_BUILD_FLAGS}", platforms=("windows",))),
    "windows": op(cmd(f"{DOTNET} build {sh(WINDOWS_SLN)} -p:Platform=x64 {DOTNET_BUILD_FLAGS}", platforms=("windows",))),
    "fyne": op(cmd("mkdir -p out/dev"), cmd(f"{FYNE_GO} build -o ../../../out/dev/gui-for-cli-fyne .", cwd="exp-platform/go/fyne")),
    "flutter": op(
        cmd(
            f"{FLUTTER_SETUP} && flutter build macos --release "
            f"--dart-define=GFC_REPO_ROOT={sh(Path('.').resolve())} --dart-define=GFC_BUNDLE_ROOT={sh(BUNDLE_ROOT)}",
            cwd="exp-platform/dart/flutter",
        )
    ),
    "android": op(cmd(f"{KOTLIN_PREFIX} {KOTLIN_GRADLE} {KOTLIN_GRADLE_FLAGS} :androidApp:assembleDebug", cwd=KOTLIN_COMPOSE_DIR)),
    "compose-desktop": op(
        cmd(f"{KOTLIN_PREFIX} {KOTLIN_GRADLE} {KOTLIN_GRADLE_FLAGS} :desktopApp:packageDistributionForCurrentOS", cwd=KOTLIN_COMPOSE_DIR)
    ),
    "swiftui-macos": op(
        cmd(xcodebuild("GUIForCLIMac", "Debug", MACOS_DESTINATION), platforms=("darwin",)),
        deps=project(),
    ),
    "appkit-macos": op(
        cmd(xcodebuild("GUIForCLIAppKit", "Debug", MACOS_DESTINATION), platforms=("darwin",)),
        deps=project(),
    ),
    "objc-appkit-macos": op(
        cmd(xcodebuild("GUIForCLIObjCAppKit", "Debug", MACOS_DESTINATION), platforms=("darwin",)),
        deps=project(),
    ),
    "objc-appkit-macos-release": op(
        cmd(xcodebuild("GUIForCLIObjCAppKit", "Release", MACOS_DESTINATION), platforms=("darwin",)),
        deps=project(),
    ),
    "ios-simulator": op(
        cmd(xcodebuild("GUIForCLIiOS", "Debug", IOS_SIM_DESTINATION), platforms=("darwin",)),
        cmd(materialize_ios_resources(IOS_SIM_APP, IOS_SIM_DEMO_BUNDLE), platforms=("darwin",)),
        deps=project(),
    ),
    "ios-device": op(
        cmd(xcodebuild("GUIForCLIiOS", "Debug", IOS_DEVICE_DESTINATION), platforms=("darwin",)),
        cmd(materialize_ios_resources(IOS_DEVICE_APP, IOS_DEVICE_DEMO_BUNDLE), platforms=("darwin",)),
        deps=project(),
    ),
}

RUN: dict[str, Operation] = {
    "cli": op(cmd(swift_env(f"swift run --package-path {sh(APPLE_DIR)} gui-for-cli run"))),
    "webui": op(
        cmd(f"node platform/typescript/dist/web/src/server/main.js --bundle {sh(BUNDLE_ROOT)} --port {sh(WEB_PORT)}"),
        deps=(("build", "webui"),),
    ),
    "webui-dev": op(cmd(f"npm run dev -- --bundle {sh(BUNDLE_ROOT)} --port {sh(WEB_PORT)}", cwd=TYPESCRIPT_DIR)),
    "tui": op(cmd(f"npm run tui -- --bundle {sh(BUNDLE_ROOT)}", cwd=TYPESCRIPT_DIR)),
    "nodegui": op(cmd(f"npm run nodegui -- --bundle {sh(BUNDLE_ROOT)}", cwd=TYPESCRIPT_DIR)),
    "webview-shell": op(
        cmd(f"GFC_REPO_ROOT={sh(Path('.').resolve())} GFC_NODE_PATH=\"$(command -v node)\" {sh(WEBVIEW_SHELL_EXE)}"),
        deps=(("build", "webview-shell"),),
    ),
    "tauri": op(cmd("npm run tauri:dev", cwd=TYPESCRIPT_DIR)),
    "dioxus": op(
        cmd(
            f"GFC_REPO_ROOT={sh(Path('.').resolve())} GFC_NODE_PATH=\"$(command -v node)\" "
            f"cargo run --release --manifest-path {sh(RUST_APPS_DIR + '/Cargo.toml')}",
            windows_command=ps(
                "$env:GFC_REPO_ROOT=(Get-Location).Path; "
                "$env:GFC_NODE_PATH=(Get-Command node).Source; "
                "cargo run --release --manifest-path exp-platform/rust/dioxus-shell/Cargo.toml"
            ),
        ),
        deps=(("build", "webui"),),
    ),
    "gtk4": op(cmd(f"{sh(GTK4_EXE)} --bundle {sh(BUNDLE_ROOT)}"), deps=(("build", "gtk4"),)),
    "slint": op(
        cmd(
            f"{sh(SLINT_EXE)} --bundle {sh(BUNDLE_ROOT)}",
            windows_command=ps(
                "$bundle = if ($env:BUNDLE) { (Resolve-Path $env:BUNDLE).Path } "
                "else { (Resolve-Path examples/WGSExtract).Path }; "
                "exp-platform/rust/slint/target/release/gui-for-cli-slint.exe --bundle $bundle"
            ),
        ),
        deps=(("build", "slint"),),
    ),
    "raygui": op(cmd(f"{sh(RAYGUI_EXE)} --bundle {sh(BUNDLE_ROOT)}"), deps=(("build", "raygui"),)),
    "raygui-c": op(
        cmd(f"{sh(RAYGUI_C_EXE)} --bundle {sh(BUNDLE_ROOT)} --repo-root {sh(Path('.').resolve())}"),
        deps=(("build", "raygui-c"),),
    ),
    "imgui": op(
        cmd(
            f"{sh(IMGUI_EXE)} --bundle {sh(BUNDLE_ROOT)}",
            windows_command=ps(
                "$bundle = if ($env:BUNDLE) { (Resolve-Path $env:BUNDLE).Path } "
                "else { (Resolve-Path examples/WGSExtract).Path }; "
                "exp-platform/rust/imgui/target/release/gui-for-cli-imgui.exe --bundle $bundle"
            ),
        ),
        deps=(("build", "imgui"),),
    ),
    "iced": op(cmd(f"{sh(ICED_EXE)} --bundle {sh(BUNDLE_ROOT)}"), deps=(("build", "iced"),)),
    "makepad": op(cmd(f"{sh(MAKEPAD_EXE)} --bundle {sh(BUNDLE_ROOT)}"), deps=(("build", "makepad"),)),
    "egui": op(cmd(f"{sh(EGUI_EXE)} --bundle {sh(BUNDLE_ROOT)}"), deps=(("build", "egui"),)),
    "xilem-vello": op(
        cmd("mkdir -p tmp/xilem-vello-workspaces"),
        cmd(f"GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT=tmp/xilem-vello-workspaces {sh(XILEM_VELLO_EXE)} --bundle {sh(BUNDLE_ROOT)}"),
        deps=(("build", "xilem-vello"),),
    ),
    "gpui": op(
        cmd("rm -rf tmp/gpui-run-workspaces && mkdir -p tmp/gpui-run-workspaces"),
        cmd(
            f"GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT=tmp/gpui-run-workspaces {sh(GPUI_EXE)} "
            f"--bundle {sh(BUNDLE_ROOT)} --repo-root {sh(Path('.').resolve())}"
        ),
        deps=(("build", "gpui"),),
    ),
    "mojo": op(
        cmd("rm -rf tmp/mojo-run-workspaces && mkdir -p tmp/mojo-run-workspaces"),
        cmd(
            f"GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT={sh(str(Path('tmp/mojo-run-workspaces').resolve()))} "
            f"pixi run mojo run src/gui_for_cli_mojo.mojo --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} --once",
            cwd=MOJO_DIR,
        ),
    ),
    "imgui-cpp": op(
        cmd(f"{sh(IMGUI_CPP_EXE)} --bundle {sh(BUNDLE_ROOT)} --repo-root {sh(Path('.').resolve())}"),
        deps=(("build", "imgui-cpp"),),
    ),
    "qt-qml": op(
        cmd(f"{sh(QT_QML_EXE)} --bundle {sh(BUNDLE_ROOT)} --repo-root {sh(Path('.').resolve())}"),
        deps=(("build", "qt-qml"),),
    ),
    "avalonia": op(
        cmd(f"dotnet run --project {sh(AVALONIA_APP_PROJECT)} --no-restore -- --repo-root {sh(Path('.').resolve())} --bundle {sh(BUNDLE_ROOT)}"),
        deps=(("build", "avalonia"),),
    ),
    "windows": op(
        cmd(
            ps(
                "Get-Process -Name GUIForCLIWindows -ErrorAction SilentlyContinue | "
                "ForEach-Object { Stop-Process -Id $_.Id -Force }; "
                f"{DOTNET} build {WINDOWS_SLN} -p:Platform=x64 {DOTNET_BUILD_FLAGS}; "
                "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; "
                f"Start-Process exp-platform/windows/dotnet/GUIForCLIWindows/bin/x64/{CONFIGURATION}/"
                "net10.0-windows10.0.19041.0/win-x64/GUIForCLIWindows.exe"
            ),
            platforms=("windows",),
        )
    ),
    "nodegui-smoke": op(cmd(f"npm run nodegui:smoke -- --bundle {sh(BUNDLE_ROOT)}", cwd=TYPESCRIPT_DIR)),
    "fyne": op(
        cmd(f"GFC_FYNE_REPO_ROOT={sh(Path('.').resolve())} GFC_FYNE_BUNDLE={sh(BUNDLE_ROOT)} out/dev/gui-for-cli-fyne"),
        deps=(("build", "fyne"),),
    ),
    "textual": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m gui_for_cli_textual --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} {os.environ.get('TEXTUAL_ARGS', '')}",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/textual-workspaces",
            },
        )
    ),
    "tkinter": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m gui_for_cli_tkinter --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} {os.environ.get('TKINTER_ARGS', '')}",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/tkinter-workspaces",
            },
        )
    ),
    "wx": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m gui_for_cli_wx --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} {os.environ.get('WX_ARGS', '')}",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/wx-workspaces",
            },
        )
    ),
    "toga": op(
        cmd(
            f"python3 -m gui_for_cli_toga --repo-root {sh(Path('.').resolve())} --bundle {sh(BUNDLE_ROOT)} "
            f"--workspace-root {sh(str(Path(PYTHON_TOGA_WORKSPACE).resolve()))}",
            env={
                "PYTHONDONTWRITEBYTECODE": "1",
                "PYTHONPATH": str(Path(PYTHON_TOGA_SRC).resolve()),
            },
        )
    ),
    "flutter": op(
        cmd(
            f"{FLUTTER_SETUP} && flutter run -d macos "
            f"--dart-define=GFC_REPO_ROOT={sh(Path('.').resolve())} --dart-define=GFC_BUNDLE_ROOT={sh(BUNDLE_ROOT)}",
            cwd="exp-platform/dart/flutter",
        )
    ),
    "compose-desktop": op(
        cmd(f"{KOTLIN_PREFIX} {KOTLIN_GRADLE} {KOTLIN_GRADLE_FLAGS} :desktopApp:run --args=\"--bundle {BUNDLE_ROOT}\"", cwd=KOTLIN_COMPOSE_DIR)
    ),
    "swiftui-macos": op(cmd(f"open {sh(MACOS_APP)}", platforms=("darwin",)), deps=(("build", "swiftui-macos"),)),
    "appkit-macos": op(cmd(f"open {sh(MACOS_APPKIT_APP)}", platforms=("darwin",)), deps=(("build", "appkit-macos"),)),
    "objc-appkit-macos": op(
        cmd(f"GFC_REPO_ROOT={sh(Path('.').resolve())} GFC_BUNDLE_PATH={sh(BUNDLE_ROOT)} {sh(OBJC_APPKIT_EXE)}"),
        deps=(("build", "objc-appkit-macos"),),
    ),
    "ios-simulator": op(cmd(ios_sim_run("IOS_SIMULATOR"), platforms=("darwin",)), deps=(("build", "ios-simulator"),)),
    "ios-ipad-simulator": op(cmd(ios_sim_run("IOS_IPAD_SIMULATOR", "iPad"), platforms=("darwin",)), deps=(("build", "ios-simulator"),)),
    "ios-device": op(
        cmd(
            "if [ -n \"${IOS_DEVICE:-}\" ]; then "
            f"xcrun devicectl device install app --device \"$IOS_DEVICE\" {sh(IOS_DEVICE_APP)}; "
            f"xcrun devicectl device process launch --device \"$IOS_DEVICE\" {sh(IOS_BUNDLE_ID)}; "
            "else echo 'Skipping iOS device install: set IOS_DEVICE.' >&2; fi"
        ),
        deps=(("build", "ios-device"),),
    ),
}
