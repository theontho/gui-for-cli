"""Setup, test, lint, and format operations."""

from __future__ import annotations

from .definitions import *  # noqa: F403


SETUP: dict[str, Operation] = {
    "devtools": op(
        cmd(swift_env(f"swift package --package-path {sh(APPLE_DIR)} resolve")),
        cmd(f"cd {sh(APPLE_DIR)} && ../../scripts/tuist.sh install"),
        cmd(f"{PYTHON} scripts/dev-register.py"),
        cmd(f"{PYTHON} scripts/setup-hooks.py"),
        deps=(("setup", "webui"),),
        description="Resolve Swift packages, install Tuist, and register dev hooks.",
    ),
    "webui": op(cmd("npm install", cwd=TYPESCRIPT_DIR), description="Install Web UI npm dependencies."),
    "python": op(deps=(("setup", "textual"), ("setup", "tkinter")), description="Install Python renderer deps."),
    "textual": op(
        cmd(f"{PYTHON_PIP_ENV} {TEXTUAL_PYTHON} -m pip install -e {sh(PYTHON_SHARED_DIR)} -e {sh(TEXTUAL_DIR)}")
    ),
    "tkinter": op(
        cmd(f"{PYTHON_PIP_ENV} {TEXTUAL_PYTHON} -m pip install -e {sh(PYTHON_SHARED_DIR)} -e {sh(TKINTER_DIR)}")
    ),
    "wx": op(
        cmd(f"{PYTHON_PIP_ENV} {TEXTUAL_PYTHON} -m pip install -e {sh(PYTHON_SHARED_DIR)} -e {sh(WX_DIR + '[ui]')}")
    ),
    "toga": op(cmd(f"{PYTHON_PIP_ENV} {TEXTUAL_PYTHON} -m pip install -e {sh(PYTHON_TOGA_DIR)}")),
    "mojo": op(cmd("pixi install --locked", cwd=MOJO_DIR)),
    "apple-project": op(
        cmd(APPLE_RESOURCE_SYNC),
        cmd(f"cd {sh(APPLE_DIR)} && ../../scripts/tuist.sh generate --no-open"),
    ),
}

TEST: dict[str, Operation] = {
    "swift": op(
        cmd(APPLE_RESOURCE_SYNC),
        cmd(swift_env(f"swift test --package-path {sh(APPLE_DIR)} --parallel")),
    ),
    "webui": op(cmd("npm --prefix platform/typescript test")),
    "python": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m compileall -q exp-platform/python",
            env={"PYTHONPATH": PYTHON_WITH_TOGA_PATH},
        ),
        deps=(("test", "textual"), ("test", "tkinter"), ("test", "wx"), ("test", "toga")),
    ),
    "textual": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m unittest discover -s {sh(TEXTUAL_DIR + '/tests')}",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/textual-test-workspaces",
            },
        )
    ),
    "tkinter": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m gui_for_cli_tkinter --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} --once",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/tkinter-test-workspaces",
            },
        )
    ),
    "wx": op(
        cmd(
            f"{TEXTUAL_PYTHON} -m gui_for_cli_wx --repo-root {sh(Path('.').resolve())} "
            f"--bundle {sh(BUNDLE_ROOT)} --once",
            env={
                "PYTHONPATH": PYTHON_RENDERER_PATH,
                "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": "tmp/wx-test-workspaces",
            },
        )
    ),
    "toga": op(
        cmd(
            f"{PYTHON} -m unittest discover -s {sh(PYTHON_TOGA_DIR + '/tests')}",
            env={
                "PYTHONDONTWRITEBYTECODE": "1",
                "PYTHONPATH": str(Path(PYTHON_TOGA_SRC).resolve()),
            },
        )
    ),
    "mojo": op(cmd(f"{PYTHON} {sh(MOJO_DIR + '/tests/test_mojo_runtime.py')}")),
    "flutter": op(cmd("flutter test", cwd="exp-platform/dart/flutter")),
    "compose": op(cmd(f"{KOTLIN_PREFIX} {KOTLIN_GRADLE} {KOTLIN_GRADLE_FLAGS} :shared:test", cwd=KOTLIN_COMPOSE_DIR)),
    "android": op(
        cmd(f"{KOTLIN_PREFIX} {KOTLIN_GRADLE} {KOTLIN_GRADLE_FLAGS} :androidApp:testDebugUnitTest", cwd=KOTLIN_COMPOSE_DIR)
    ),
    "gtk4": op(cmd("cargo check --manifest-path exp-platform/rust/gtk4/Cargo.toml --no-default-features")),
    "slint": op(cmd("cargo test --manifest-path exp-platform/rust/slint/Cargo.toml")),
    "raygui": op(cmd("cargo test --manifest-path exp-platform/rust/raygui/Cargo.toml")),
    "imgui": op(cmd("cargo test --manifest-path exp-platform/rust/imgui/Cargo.toml")),
    "iced": op(cmd("cargo test --manifest-path exp-platform/rust/iced/Cargo.toml")),
    "makepad": op(cmd("cargo test --manifest-path exp-platform/rust/makepad/Cargo.toml")),
    "egui": op(cmd("cargo test --manifest-path exp-platform/rust/egui/Cargo.toml")),
    "xilem-vello": op(cmd("cargo test --manifest-path exp-platform/rust/xilem-vello/Cargo.toml")),
    "gpui": op(
        cmd("rm -rf tmp/gpui-test-workspaces && mkdir -p tmp/gpui-test-workspaces"),
        cmd(
            "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT=tmp/gpui-test-workspaces "
            "cargo test --manifest-path exp-platform/rust/gpui/Cargo.toml"
        ),
    ),
    "qt-qml": op(
        cmd(f"cmake -S exp-platform/cpp/qt-qml -B {sh(QT_QML_VALIDATE_BUILD_DIR)} -DGUI_FOR_CLI_QT_QML_VALIDATE_ONLY=ON"),
        cmd(f"cmake --build {sh(QT_QML_VALIDATE_BUILD_DIR)} --config Release"),
    ),
    "avalonia": op(
        cmd(f"dotnet restore {sh(AVALONIA_TEST_PROJECT)}"),
        cmd(f"dotnet run --project {sh(AVALONIA_TEST_PROJECT)} --no-restore"),
    ),
    "windows-core": op(cmd(f"{DOTNET} run --project {sh(WINDOWS_CORE_TEST_PROJECT)}")),
    "fyne": op(cmd(f"{FYNE_GO} test ./...", cwd="exp-platform/go/fyne")),
}

LINT: dict[str, Operation] = {
    "swift": op(
        cmd(APPLE_RESOURCE_SYNC, platforms=("darwin", "linux")),
        cmd(
            f"swift format lint --recursive {SWIFT_FORMAT_PATHS}",
            platforms=("darwin", "linux"),
        )
    ),
    "typescript": op(cmd("npm --prefix platform/typescript run check")),
    "locales": op(cmd(f"{PYTHON} tools/localization/lint_locales.py --strict")),
    "bundles": op(
        cmd(APPLE_RESOURCE_SYNC, platforms=("darwin", "linux")),
        cmd(
            swift_env(f"swift run --package-path {sh(APPLE_DIR)} gui-for-cli bundle validate --strict examples/*"),
            platforms=("darwin", "linux"),
        )
    ),
    "tools": op(cmd(f"{PYTHON} -m compileall -q tools")),
    "rust": op(
        cmd("cargo check --manifest-path exp-platform/rust/gtk4/Cargo.toml --no-default-features"),
        cmd("cargo check --manifest-path exp-platform/rust/slint/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/raygui/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/imgui/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/iced/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/makepad/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/egui/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/xilem-vello/Cargo.toml"),
        cmd("cargo check --manifest-path exp-platform/rust/gpui/Cargo.toml"),
    ),
    "go": op(
        cmd(f"{GIO_GO} test ./...", cwd="exp-platform/go/gio"),
        cmd(f"{FYNE_GO} test ./...", cwd="exp-platform/go/fyne"),
    ),
    "cpp": op(
        cmd(f"cmake -S exp-platform/cpp/qt-qml -B {sh(QT_QML_VALIDATE_BUILD_DIR)} -DGUI_FOR_CLI_QT_QML_VALIDATE_ONLY=ON"),
        cmd(f"cmake --build {sh(QT_QML_VALIDATE_BUILD_DIR)} --config Release"),
    ),
    "dotnet": op(
        cmd(f"dotnet restore {sh(AVALONIA_TEST_PROJECT)}"),
        cmd(f"dotnet build {sh(AVALONIA_APP_PROJECT)} --no-restore"),
    ),
    "python": op(cmd(f"{PYTHON} -m compileall -q exp-platform/python")),
}

FORMAT: dict[str, Operation] = {
    "swift": op(
        cmd(
            f"swift format format --in-place --recursive {SWIFT_FORMAT_PATHS}",
            platforms=("darwin", "linux"),
        )
    ),
    "rust": op(
        cmd("cargo fmt --manifest-path exp-platform/rust/gtk4/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/slint/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/raygui/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/imgui/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/iced/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/makepad/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/egui/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/xilem-vello/Cargo.toml"),
        cmd("cargo fmt --manifest-path exp-platform/rust/gpui/Cargo.toml"),
    ),
}
