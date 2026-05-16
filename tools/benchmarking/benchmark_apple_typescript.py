"""Apple and TypeScript benchmark commands."""

from __future__ import annotations

import sys
from pathlib import Path

from benchmark_core import Context, macos_process, make, repo_path, run


def benchmark_swiftui(ctx: Context) -> None:
    make(ctx, "build-swift-release")
    app = ctx.derived_data_path / "Build/Products/Release/GUI for CLI.app"
    macos_process(
        ctx,
        name="SwiftUI macOS",
        ready_metric="window_appeared",
        output=ctx.release_dir / "swift/benchmark-macos.json",
        artifacts=[app],
        env={"GFC_BENCHMARK_STARTUP": "1"},
        command=[str(app / "Contents/MacOS/GUI for CLI")],
    )


def benchmark_appkit(ctx: Context) -> None:
    make(ctx, "build-appkit-release")
    app = ctx.derived_data_path / "Build/Products/Release/swift appkit test.app"
    macos_process(
        ctx,
        name="Swift AppKit macOS",
        ready_metric="window_appeared",
        output=ctx.release_dir / "appkit/benchmark-macos.json",
        artifacts=[app],
        command=[str(app / "Contents/MacOS/swift appkit test"), "--benchmark"],
    )


def benchmark_objc_appkit(ctx: Context) -> None:
    make(ctx, "build-objc-appkit-release")
    app = ctx.derived_data_path / "Build/Products/Release/GUI for CLI ObjC AppKit Test.app"
    macos_process(
        ctx,
        name="Objective-C AppKit macOS",
        ready_metric="window_appeared",
        output=ctx.release_dir / "objc-appkit/benchmark-macos.json",
        artifacts=[app],
        command=[str(app / "Contents/MacOS/GUI for CLI ObjC AppKit Test"), "--benchmark"],
    )


def benchmark_ios_sim(ctx: Context) -> None:
    make(ctx, "build-ios-sim")
    app = ctx.derived_data_path / "Build/Products/Debug-iphonesimulator/GUI for CLI.app"
    run(
        ctx,
        [
            sys.executable,
            "tools/benchmarking/ios_sim.py",
            "--app",
            str(app),
            "--bundle-id",
            ctx.env.get("IOS_BUNDLE_ID", "dev.guiforcli.gui-for-cli.ios"),
            "--simulator",
            ctx.env.get("IOS_SIMULATOR", "booted"),
            "--samples",
            str(ctx.samples),
            "--output",
            str(ctx.release_dir / "ios-sim/benchmark-macos.json"),
            "--artifact",
            str(app),
        ],
    )


def benchmark_webui_browser(ctx: Context) -> None:
    run(ctx, ["npm", "--prefix", "platform/typescript", "run", "build"])
    run(ctx, ["npm", "--prefix", "platform/typescript", "exec", "--", "playwright", "install", "chromium"])
    command = [
        "node",
        "tools/benchmarking/browser_benchmark.mjs",
        "--samples",
        str(ctx.samples),
        "--bundle",
        str(ctx.bundle_root),
        "--output",
        str(ctx.release_dir / "webui-browser/benchmark.json"),
    ]
    if ctx.headless_browser:
        command.append("--headless")
    if ctx.no_focus:
        command.append("--preserve-focus")
    run(ctx, command)


def benchmark_webview(ctx: Context) -> None:
    make(ctx, "build-webview-release")
    app = ctx.release_dir / "webview/GUI for CLI WebView Shell.app"
    macos_process(
        ctx,
        name="WebView shell macOS",
        ready_metric="webAppRendered",
        output=ctx.release_dir / "webview/benchmark-macos.json",
        artifacts=[app],
        command=[str(app / "Contents/MacOS/GUIForCLIWebViewShell")],
    )


def benchmark_tauri(ctx: Context) -> None:
    make(ctx, "build-tauri-release")
    app = ctx.release_dir / "tauri/GUI for CLI WebUI.app"
    macos_process(
        ctx,
        name="Tauri WebUI macOS",
        ready_metric="webAppRenderedInPage",
        output=ctx.release_dir / "tauri/benchmark-macos.json",
        artifacts=[app],
        command=[str(app / "Contents/MacOS/gui-for-cli-webui-tauri")],
    )


def benchmark_electron(ctx: Context) -> None:
    make(ctx, "build-electron-release")
    if ctx.dry_run:
        electron_app = ctx.release_dir / "electron/<electron-app>.app"
        electron_exe = electron_app / "Contents/MacOS/GUI for CLI Electron"
    else:
        candidates = sorted((ctx.release_dir / "electron").glob("**/*.app/Contents/MacOS/GUI for CLI Electron"))
        if not candidates:
            raise RuntimeError(f"Electron executable not found under {ctx.release_dir / 'electron'}")
        electron_exe = candidates[0]
        electron_app = Path(str(electron_exe).split(".app/Contents/MacOS/", 1)[0] + ".app")
    macos_process(
        ctx,
        name="Electron WebUI macOS",
        ready_metric="webAppRendered",
        output=ctx.release_dir / "electron/benchmark-macos.json",
        artifacts=[electron_app],
        command=[str(electron_exe)],
    )


def benchmark_dioxus(ctx: Context) -> None:
    make(ctx, "build-dioxus-release")
    exe = ctx.release_dir / "dioxus/gui-for-cli-webui-dioxus"
    macos_process(
        ctx,
        name="Dioxus WebUI macOS",
        ready_metric="windowShown",
        output=ctx.release_dir / "dioxus/benchmark-macos.json",
        artifacts=[ctx.release_dir / "dioxus"],
        env={"GFC_BENCH_EXIT_AFTER_READY": "1"},
        command=[str(exe)],
    )


def benchmark_nodegui(ctx: Context) -> None:
    run(ctx, ["npm", "--prefix", "platform/typescript", "run", "build:nodegui"])
    macos_process(
        ctx,
        name="NodeGui macOS",
        ready_metric="windowShown",
        output=ctx.release_dir / "nodegui/benchmark-macos.json",
        artifacts=[repo_path("platform/typescript/dist/exp/nodegui"), repo_path("platform/typescript/dist/shared")],
        cwd=repo_path("platform/typescript"),
        command=["./node_modules/.bin/qode", "dist/exp/nodegui/main.js", "--benchmark", "--no-setup", "--bundle", str(ctx.bundle_root)],
    )


def benchmark_tui(ctx: Context) -> None:
    run(ctx, ["npm", "--prefix", "platform/typescript", "run", "build:tui"])
    macos_process(
        ctx,
        name="TypeScript TUI",
        ready_metric="render",
        output=ctx.release_dir / "tui/benchmark.json",
        artifacts=[repo_path("platform/typescript/dist/tui"), repo_path("platform/typescript/dist/shared")],
        command=["node", "platform/typescript/dist/tui/main.js", "--bundle", str(ctx.bundle_root), "--once", "--benchmark", "--no-setup"],
    )
