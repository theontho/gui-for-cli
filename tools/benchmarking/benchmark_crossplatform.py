"""Cross-platform benchmark commands."""

from __future__ import annotations

import shlex
import shutil
import sys
from pathlib import Path

from benchmark_core import Context, REPO, kotlin_env, macos_process, make, mkdir, remove_files, remove_tree, repo_path, run


def benchmark_toga(ctx: Context) -> None:
    make(ctx, "setup-toga")
    workspace = repo_path(ctx.env.get("PYTHON_TOGA_WORKSPACE", "tmp/python-toga-workspace"))
    output = repo_path(ctx.env.get("PYTHON_TOGA_BENCHMARK_OUTPUT", str(ctx.release_dir / "toga/benchmark.json")))
    mkdir(ctx, output.parent, workspace)
    macos_process(
        ctx,
        name="Python Toga",
        ready_metric="ui_ready",
        output=output,
        artifacts=[repo_path("exp-platform/python/toga")],
        timeout=30,
        env={"GUI_FOR_CLI_OFFLINE": "1", "PYTHONPATH": str(repo_path("exp-platform/python/toga/src"))},
        command=[
            ctx.textual_python,
            "-m",
            "gui_for_cli_toga",
            "--repo-root",
            str(REPO),
            "--bundle",
            str(ctx.bundle_root),
            "--workspace-root",
            str(workspace),
            "--benchmark",
            "--benchmark-full",
        ],
    )


def benchmark_gio(ctx: Context) -> None:
    make(ctx, "build-gio-release")
    exe = ctx.release_dir / "gio/gui-for-cli-gio"
    macos_process(ctx, name="Go Gio", ready_metric="firstFrameRendered", output=ctx.release_dir / "gio/benchmark-macos.json", artifacts=[exe], env={"GUI_FOR_CLI_OFFLINE": "1"}, command=[str(exe)])


def benchmark_avalonia(ctx: Context) -> None:
    make(ctx, "restore-avalonia")
    project = repo_path("exp-platform/dotnet/avalonia/GUIForCLIAvalonia/GUIForCLIAvalonia.csproj")
    run(ctx, ["dotnet", "build", str(project), "-c", "Release", "--no-restore"])
    output_dir = repo_path("exp-platform/dotnet/avalonia/GUIForCLIAvalonia/bin/Release/net10.0")
    macos_process(
        ctx,
        name="Avalonia",
        ready_metric="GFC_AVALONIA_FIRST_RENDER",
        output=ctx.release_dir / "avalonia/benchmark.json",
        artifacts=[output_dir],
        timeout=45,
        env={"GUI_FOR_CLI_OFFLINE": "1"},
        command=["dotnet", str(output_dir / "GUIForCLIAvalonia.dll"), "--repo-root", str(REPO), "--bundle", str(ctx.bundle_root), "--benchmark", "--once"],
    )


def benchmark_compose_desktop(ctx: Context) -> None:
    gradle = shlex.split(ctx.env.get("KOTLIN_GRADLE", "gradle"))
    flags = shlex.split(ctx.env.get("KOTLIN_GRADLE_FLAGS", "--console=plain --quiet"))
    macos_process(
        ctx,
        name="Compose Desktop",
        ready_metric="ui_ready",
        output=ctx.release_dir / "compose-desktop/benchmark-macos.json",
        artifacts=[repo_path("exp-platform/kotlin/compose/desktopApp")],
        timeout=45,
        cwd=repo_path("exp-platform/kotlin/compose"),
        env={"GUI_FOR_CLI_OFFLINE": "1", **kotlin_env(ctx)},
        command=[*gradle, *flags, ":desktopApp:run", f"--args=--bundle {ctx.bundle_root} --benchmark --once"],
    )


def benchmark_android(ctx: Context) -> None:
    make(ctx, "build-android")
    apk = repo_path("exp-platform/kotlin/compose/androidApp/build/outputs/apk/debug/androidApp-debug.apk")
    run(ctx, [sys.executable, "tools/benchmarking/android.py", "--apk", str(apk), "--samples", str(ctx.samples), "--output", str(ctx.release_dir / "android/benchmark.json"), "--artifact", str(apk)])


def benchmark_fyne(ctx: Context) -> None:
    make(ctx, "build-fyne-release")
    exe = ctx.release_dir / "fyne/gui-for-cli-fyne"
    macos_process(ctx, name="Fyne", ready_metric="firstFrameRendered", output=ctx.release_dir / "fyne/benchmark-macos.json", artifacts=[exe], env={"GUI_FOR_CLI_OFFLINE": "1"}, command=[str(exe)])


def benchmark_python(ctx: Context, *, kind: str, output: Path, workspace: Path, module: str, setup_target: str | None) -> None:
    if setup_target:
        make(ctx, setup_target)
    mkdir(ctx, output.parent)
    renderer_path = ":".join(str(repo_path(part)) for part in ("exp-platform/python/shared", "exp-platform/python/textual", "exp-platform/python/tkinter", "exp-platform/python/wx"))
    macos_process(
        ctx,
        name=f"Python {'wxPython' if kind == 'wx' else kind.title()}",
        ready_metric="ui_ready",
        output=output,
        artifacts=[repo_path("exp-platform/python/shared"), repo_path(f"exp-platform/python/{kind}")],
        timeout=30,
        env={"GUI_FOR_CLI_OFFLINE": "1", "PYTHONPATH": renderer_path, "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(workspace)},
        command=[ctx.textual_python, "-m", module, "--repo-root", str(REPO), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--benchmark-output", str(output)],
    )


def benchmark_textual(ctx: Context) -> None:
    benchmark_python(ctx, kind="textual", output=repo_path(ctx.env.get("TEXTUAL_BENCHMARK_OUTPUT", str(ctx.release_dir / "textual/benchmark.json"))), workspace=repo_path("tmp/textual-benchmark-workspaces"), module="gui_for_cli_textual", setup_target="setup-textual")


def benchmark_tkinter(ctx: Context) -> None:
    benchmark_python(ctx, kind="tkinter", output=repo_path(ctx.env.get("TKINTER_BENCHMARK_OUTPUT", str(ctx.release_dir / "tkinter/benchmark.json"))), workspace=repo_path("tmp/tkinter-benchmark-workspaces"), module="gui_for_cli_tkinter", setup_target=None)


def benchmark_wx(ctx: Context) -> None:
    benchmark_python(ctx, kind="wx", output=repo_path(ctx.env.get("WX_BENCHMARK_OUTPUT", str(ctx.release_dir / "wx/benchmark.json"))), workspace=repo_path("tmp/wx-benchmark-workspaces"), module="gui_for_cli_wx", setup_target="setup-wx")


def benchmark_mojo(ctx: Context) -> None:
    output = repo_path(ctx.env.get("MOJO_BENCHMARK_OUTPUT", str(ctx.release_dir / "mojo/benchmark.json")))
    workspace = repo_path("tmp/mojo-benchmark-workspaces")
    mkdir(ctx, output.parent, workspace)
    macos_process(
        ctx,
        name="Mojo core renderer",
        ready_metric="uiReady",
        output=output,
        artifacts=[repo_path("exp-platform/mojo/src")],
        timeout=45,
        cwd=repo_path("exp-platform/mojo"),
        env={"GUI_FOR_CLI_OFFLINE": "1", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(workspace)},
        command=["pixi", "run", "mojo", "run", "src/gui_for_cli_mojo.mojo", "--repo-root", str(REPO), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once", "--benchmark-output", str(output.resolve())],
    )


def benchmark_flutter(ctx: Context) -> None:
    if shutil.which("pwsh") is None:
        print("Skipping Windows Flutter benchmark: pwsh is not installed.", file=sys.stderr)
        return
    run(
        ctx,
        [
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "tools/benchmarking/benchmark_flutter.ps1",
            "-Samples",
            str(ctx.samples),
        ],
    )


def benchmark_startup_sequential(ctx: Context) -> None:
    for target in ("build-macos", "build-tauri-release", "flutter-build", "build-slint"):
        make(ctx, target)
    command = ["bash", "tools/benchmarking/startup_sequential.sh", *ctx.launch_args]
    if ctx.dry_run and "--dry-run" not in command:
        command.append("--dry-run")
    run(ctx, command)


def benchmark_flutter_macos(ctx: Context) -> None:
    flutter_dir = repo_path("exp-platform/dart/flutter")
    benchmark_output = ctx.env.get("FLUTTER_BENCHMARK_OUTPUT", "/tmp/gui-for-cli-flutter-benchmark.txt")
    run(ctx, ["flutter", "create", "--empty", "--platforms=macos", "--project-name", "gui_for_cli_flutter", "."], cwd=flutter_dir)
    for entitlement in ("DebugProfile", "Release"):
        run(ctx, ["/usr/libexec/PlistBuddy", "-c", "Set :com.apple.security.app-sandbox false", f"macos/Runner/{entitlement}.entitlements"], cwd=flutter_dir)
    run(ctx, [sys.executable, "../../../scripts/configure-flutter-macos-window.py", "macos/Runner/MainFlutterWindow.swift", "--width", ctx.env.get("FLUTTER_WINDOW_WIDTH", "1344"), "--height", ctx.env.get("FLUTTER_WINDOW_HEIGHT", "864")], cwd=flutter_dir)
    remove_files(ctx, flutter_dir, ["README.md", "analysis_options.yaml", "test/widget_test.dart"])
    run(ctx, ["find", ".", "-maxdepth", "1", "-name", "*.iml", "-delete"], cwd=flutter_dir)
    run(ctx, ["flutter", "build", "macos", "--release", f"--dart-define=GFC_REPO_ROOT={REPO}", f"--dart-define=GFC_BUNDLE_ROOT={ctx.bundle_root}", f"--dart-define=GFC_BENCHMARK_OUTPUT={benchmark_output}"], cwd=flutter_dir)
    run(ctx, [sys.executable, "tools/benchmarking/flutter_macos.py", "exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app", "--runs", str(ctx.samples), "--marker", benchmark_output, "--output", str(ctx.release_dir / "flutter/benchmark-macos.json")])


def benchmark_rust_binary(ctx: Context, *, target: str, name: str, ready_metric: str, output: Path, artifact: Path, command: list[str], env: dict[str, str] | None = None) -> None:
    make(ctx, target)
    macos_process(ctx, name=name, ready_metric=ready_metric, output=output, artifacts=[artifact], env={"GUI_FOR_CLI_OFFLINE": "1", **(env or {})}, command=command)


def benchmark_gtk4(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/gtk4/target/release/gui-for-cli-gtk4")
    benchmark_rust_binary(ctx, target="build-gtk4", name="GTK4/libadwaita", ready_metric="ui_ready", output=ctx.release_dir / "gtk4/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once"])


def benchmark_slint(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/slint/target/release/gui-for-cli-slint")
    benchmark_rust_binary(ctx, target="build-slint", name="Slint", ready_metric="ui_ready", output=ctx.release_dir / "slint/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once"])


def benchmark_raygui(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/raygui/target/release/gui-for-cli-raygui")
    benchmark_rust_binary(ctx, target="build-raygui", name="Rust Raygui", ready_metric="content_ready", output=ctx.release_dir / "raygui/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--once"])


def benchmark_raygui_c(ctx: Context) -> None:
    make(ctx, "build-raygui-c")
    exe = repo_path("exp-platform/c/raygui/build/gui-for-cli-raygui-c")
    command = [str(exe), "--bundle", str(ctx.bundle_root), "--repo-root", str(REPO), "--benchmark", "--benchmark-full", "--once"]
    env = {"GUI_FOR_CLI_OFFLINE": "1"}
    if shutil.which("caffeinate"):
        command = ["caffeinate", "-u", "-t", "5", "env", "GUI_FOR_CLI_OFFLINE=1", *command]
        env = {}
    macos_process(ctx, name="C Raygui", ready_metric="ui_ready", output=ctx.release_dir / "raygui-c/benchmark.json", artifacts=[exe], env=env, command=command)


def benchmark_imgui(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/imgui/target/release/gui-for-cli-imgui")
    benchmark_rust_binary(ctx, target="build-imgui", name="Rust Dear ImGui", ready_metric="ui_ready", output=ctx.release_dir / "imgui/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once"])


def benchmark_iced(ctx: Context) -> None:
    make(ctx, "build-iced")
    remove_tree(ctx, repo_path("tmp/iced-workspaces"))
    mkdir(ctx, ctx.release_dir / "iced", repo_path("tmp/iced-workspaces"))
    exe = repo_path("exp-platform/rust/iced/target/release/gui-for-cli-iced")
    macos_process(ctx, name="Iced", ready_metric="ui_ready", output=ctx.release_dir / "iced/benchmark.json", artifacts=[exe], env={"GUI_FOR_CLI_OFFLINE": "1", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(repo_path("tmp/iced-workspaces"))}, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once", "--benchmark-output", str(ctx.release_dir / "iced/benchmark.txt")])


def benchmark_makepad(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/makepad/target/release/gui-for-cli-makepad")
    benchmark_rust_binary(ctx, target="build-makepad", name="Makepad", ready_metric="ui_ready", output=ctx.release_dir / "makepad/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once"])


def benchmark_egui(ctx: Context) -> None:
    exe = repo_path("exp-platform/rust/egui/target/release/gui-for-cli-egui")
    benchmark_rust_binary(ctx, target="build-egui", name="Rust egui", ready_metric="ui_ready", output=ctx.release_dir / "egui/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--once"])


def benchmark_xilem_vello(ctx: Context) -> None:
    make(ctx, "build-xilem-vello")
    remove_tree(ctx, repo_path("tmp/xilem-vello-workspaces"))
    mkdir(ctx, ctx.release_dir / "xilem-vello", repo_path("tmp/xilem-vello-workspaces"))
    exe = repo_path("exp-platform/rust/xilem-vello/target/release/gui-for-cli-xilem-vello")
    macos_process(ctx, name="Rust Xilem/Vello", ready_metric="ui_ready", output=ctx.release_dir / "xilem-vello/benchmark.json", artifacts=[exe], env={"GUI_FOR_CLI_OFFLINE": "1", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(repo_path("tmp/xilem-vello-workspaces"))}, command=[str(exe), "--bundle", str(ctx.bundle_root), "--benchmark", "--benchmark-full", "--benchmark-output", str(ctx.release_dir / "xilem-vello/benchmark.txt")])


def benchmark_gpui(ctx: Context) -> None:
    make(ctx, "build-gpui")
    remove_tree(ctx, repo_path("tmp/gpui-workspaces"))
    mkdir(ctx, ctx.release_dir / "gpui", repo_path("tmp/gpui-workspaces"))
    exe = repo_path("exp-platform/rust/gpui/target/release/gui-for-cli-gpui")
    macos_process(ctx, name="Rust GPUI", ready_metric="ui_ready", output=ctx.release_dir / "gpui/benchmark.json", artifacts=[exe], env={"GUI_FOR_CLI_OFFLINE": "1", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(repo_path("tmp/gpui-workspaces"))}, command=[str(exe), "--bundle", str(ctx.bundle_root), "--repo-root", str(REPO), "--benchmark", "--benchmark-full", "--benchmark-output", str(ctx.release_dir / "gpui/benchmark.txt")])


def benchmark_imgui_cpp(ctx: Context) -> None:
    exe = repo_path("exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp")
    benchmark_rust_binary(ctx, target="build-imgui-cpp", name="C++ Dear ImGui", ready_metric="ui_ready", output=ctx.release_dir / "imgui-cpp/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--repo-root", str(REPO), "--benchmark", "--benchmark-full", "--once"])


def benchmark_qt_qml(ctx: Context) -> None:
    exe = repo_path("exp-platform/cpp/qt-qml/build/gui-for-cli-qt-qml")
    benchmark_rust_binary(ctx, target="build-qt-qml", name="Qt 6/QML", ready_metric="ui_ready", output=ctx.release_dir / "qt-qml/benchmark.json", artifact=exe, command=[str(exe), "--bundle", str(ctx.bundle_root), "--repo-root", str(REPO), "--benchmark", "--benchmark-full", "--once"])
