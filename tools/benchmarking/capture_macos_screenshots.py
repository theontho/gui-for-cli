#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import select
import shlex
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import Quartz


REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "docs/ai/screenshots"
BUNDLE = REPO / "examples/WGSExtract"
NODE = (
    subprocess.run(["/bin/sh", "-lc", "command -v node"], text=True, capture_output=True)
    .stdout.strip()
    or "/opt/homebrew/bin/node"
)
IOS_APP = REPO / "platform/apple/DerivedData/Build/Products/Debug-iphonesimulator/GUI for CLI.app"
IOS_BUNDLE_ID = os.environ.get("IOS_BUNDLE_ID", "dev.guiforcli.gui-for-cli.ios")
ANDROID_APK = REPO / "exp-platform/kotlin/compose/androidApp/build/outputs/apk/debug/androidApp-debug.apk"
ANDROID_ACTIVITY = "dev.guiforcli.compose.android/.MainActivity"


@dataclass
class Surface:
    name: str
    kind: str
    command: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)
    cwd: Path = REPO
    wait: float = 4.0
    owners: list[str] = field(default_factory=list)


BASE_ENV = {
    "GUI_FOR_CLI_OFFLINE": "1",
    "GFC_REPO_ROOT": str(REPO),
    "GFC_NODE_PATH": NODE,
    "GFC_FYNE_REPO_ROOT": str(REPO),
    "GFC_FYNE_BUNDLE": str(BUNDLE),
}


SURFACES: list[Surface] = [
    Surface("swiftui-macos", "process", [str(REPO / "out/release/swift/GUI for CLI.app/Contents/MacOS/GUI for CLI")], owners=["GUI for CLI"]),
    Surface("swift-appkit", "process", [str(REPO / "out/release/appkit/swift appkit test.app/Contents/MacOS/swift appkit test")], owners=["swift appkit test"]),
    Surface("objc-appkit", "process", [str(REPO / "platform/apple/DerivedData/Build/Products/Release/GUI for CLI ObjC AppKit Test.app/Contents/MacOS/GUI for CLI ObjC AppKit Test")], owners=["GUI for CLI ObjC AppKit Test"]),
    Surface("ios-simulator", "ios"),
    Surface("webview", "process", [str(REPO / "out/release/webview/GUI for CLI WebView Shell.app/Contents/MacOS/GUIForCLIWebViewShell")], owners=["GUIForCLIWebViewShell"]),
    Surface("tauri", "process", [str(REPO / "out/release/tauri/GUI for CLI WebUI.app/Contents/MacOS/gui-for-cli-webui-tauri")], owners=["gui-for-cli-webui-tauri", "GUI for CLI WebUI"]),
    Surface("electron", "process", [str(REPO / "out/release/electron/GUI for CLI Electron-darwin-arm64/GUI for CLI Electron.app/Contents/MacOS/GUI for CLI Electron")], owners=["GUI for CLI Electron"]),
    Surface("browser-webui", "command", ["node", "tools/benchmarking/browser_screenshot.mjs", "--bundle", str(BUNDLE), "--output", str(OUT / "browser-webui.png")], wait=8.0),
    Surface("dioxus", "process", [str(REPO / "out/release/dioxus/gui-for-cli-webui-dioxus")], owners=["gui-for-cli-webui-dioxus"]),
    Surface("nodegui", "process", ["npm", "--prefix", "platform/typescript", "run", "nodegui", "--", "--bundle", str(BUNDLE), "--no-setup"], owners=["qode", "node", "GUI for CLI"], wait=8.0),
    Surface("typescript-tui", "terminal", ["npm", "--prefix", "platform/typescript", "run", "tui", "--", "--bundle", str(BUNDLE)], wait=5.0),
    Surface("python-textual", "terminal", ["python3", "-m", "gui_for_cli_textual", "--repo-root", str(REPO), "--bundle", str(BUNDLE)], env={"PYTHONPATH": "exp-platform/python/shared:exp-platform/python/textual:exp-platform/python/tkinter:exp-platform/python/wx", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(REPO / "tmp/textual-screenshot-workspaces")}, wait=5.0),
    Surface("python-tkinter", "process", ["python3", "-m", "gui_for_cli_tkinter", "--repo-root", str(REPO), "--bundle", str(BUNDLE)], env={"PYTHONPATH": "exp-platform/python/shared:exp-platform/python/textual:exp-platform/python/tkinter:exp-platform/python/wx", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(REPO / "tmp/tkinter-screenshot-workspaces")}, owners=["Python", "python3"], wait=4.0),
    Surface("python-wxpython", "process", ["python3", "-m", "gui_for_cli_wx", "--repo-root", str(REPO), "--bundle", str(BUNDLE)], env={"PYTHONPATH": "exp-platform/python/shared:exp-platform/python/textual:exp-platform/python/tkinter:exp-platform/python/wx", "GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(REPO / "tmp/wx-screenshot-workspaces")}, owners=["Python", "python3"], wait=4.0),
    Surface("python-toga", "process", ["python3", "-m", "gui_for_cli_toga", "--repo-root", str(REPO), "--bundle", str(BUNDLE), "--workspace-root", str(REPO / "tmp/python-toga-screenshot-workspace")], env={"PYTHONPATH": str(REPO / "exp-platform/python/toga/src")}, owners=["Python", "python3"], wait=6.0),
    Surface("gio", "process", [str(REPO / "out/release/gio/gui-for-cli-gio")], owners=["gui-for-cli-gio"], wait=5.0),
    Surface("fyne", "process", [str(REPO / "out/release/fyne/gui-for-cli-fyne")], owners=["gui-for-cli-fyne"], wait=5.0),
    Surface("flutter-macos", "process", [str(REPO / "exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app/Contents/MacOS/gui_for_cli_flutter")], owners=["gui_for_cli_flutter"], wait=6.0),
    Surface("android-emulator", "android", wait=8.0),
    Surface("gtk4", "process", [str(REPO / "exp-platform/rust/gtk4/target/release/gui-for-cli-gtk4")], owners=["gui-for-cli-gtk4"], wait=4.0),
    Surface("slint", "process", [str(REPO / "exp-platform/rust/slint/target/release/gui-for-cli-slint"), "--bundle", str(BUNDLE)], owners=["gui-for-cli-slint"], wait=4.0),
    Surface("raygui", "process", [str(REPO / "exp-platform/rust/raygui/target/release/gui-for-cli-raygui"), "--bundle", str(BUNDLE)], owners=["gui-for-cli-raygui"], wait=4.0),
    Surface("raygui-c", "process", [str(REPO / "exp-platform/c/raygui/build/gui-for-cli-raygui-c"), "--bundle", str(BUNDLE), "--repo-root", str(REPO)], owners=["gui-for-cli-raygui-c"], wait=4.0),
    Surface("rust-imgui", "process", [str(REPO / "exp-platform/rust/imgui/target/release/gui-for-cli-imgui"), "--bundle", str(BUNDLE)], owners=["gui-for-cli-imgui"], wait=4.0),
    Surface("iced", "process", [str(REPO / "exp-platform/rust/iced/target/release/gui-for-cli-iced"), "--bundle", str(BUNDLE)], owners=["gui-for-cli-iced"], wait=4.0),
    Surface("makepad", "process", [str(REPO / "exp-platform/rust/makepad/target/release/gui-for-cli-makepad")], owners=["gui-for-cli-makepad"], wait=12.0),
    Surface("egui", "process", [str(REPO / "exp-platform/rust/egui/target/release/gui-for-cli-egui"), "--bundle", str(BUNDLE)], owners=["gui-for-cli-egui"], wait=4.0),
    Surface("xilem-vello", "process", [str(REPO / "exp-platform/rust/xilem-vello/target/release/gui-for-cli-xilem-vello"), "--bundle", str(BUNDLE)], env={"GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(REPO / "tmp/xilem-vello-screenshot-workspaces")}, owners=["gui-for-cli-xilem-vello"], wait=5.0),
    Surface("gpui", "process", [str(REPO / "exp-platform/rust/gpui/target/release/gui-for-cli-gpui"), "--bundle", str(BUNDLE), "--repo-root", str(REPO)], env={"GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT": str(REPO / "tmp/gpui-screenshot-workspaces")}, owners=["gui-for-cli-gpui"], wait=5.0),
    Surface("cpp-imgui", "process", [str(REPO / "exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp"), "--bundle", str(BUNDLE), "--repo-root", str(REPO)], owners=["gui-for-cli-imgui-cpp"], wait=4.0),
    Surface("qt-qml", "process", [str(REPO / "exp-platform/cpp/qt-qml/build/gui-for-cli-qt-qml"), "--bundle", str(BUNDLE), "--repo-root", str(REPO)], owners=["gui-for-cli-qt-qml"], wait=5.0),
    Surface("avalonia", "process", ["dotnet", "run", "--project", "exp-platform/dotnet/avalonia/GUIForCLIAvalonia/GUIForCLIAvalonia.csproj", "-c", "Release", "--no-build", "--no-restore", "--", "--repo-root", str(REPO), "--bundle", str(BUNDLE)], owners=["GUIForCLIAvalonia"], wait=7.0),
    Surface("compose-desktop", "process", ["/bin/sh", "-c", f'cd {shlex.quote(str(REPO / "exp-platform/kotlin/compose"))} && gradle --console=plain :desktopApp:run "--args=--bundle {shlex.quote(str(BUNDLE))}"'], env={"JAVA_HOME": "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"}, owners=["MainKt", "GUI for CLI Compose Desktop"], wait=90.0),
]


def windows(include_offscreen: bool = False) -> list[dict]:
    options = Quartz.kCGWindowListExcludeDesktopElements
    options |= Quartz.kCGWindowListOptionAll if include_offscreen else Quartz.kCGWindowListOptionOnScreenOnly
    return Quartz.CGWindowListCopyWindowInfo(
        options,
        Quartz.kCGNullWindowID,
    ) or []


def visible_window_candidates(pids: set[int], owners: list[str], include_offscreen: bool = False) -> list[dict]:
    result = []
    for window in windows(include_offscreen=include_offscreen):
        bounds = window.get("kCGWindowBounds") or {}
        width = bounds.get("Width", 0)
        height = bounds.get("Height", 0)
        if window.get("kCGWindowLayer") != 0 or width < 120 or height < 80:
            continue
        pid = int(window.get("kCGWindowOwnerPID", -1))
        owner = str(window.get("kCGWindowOwnerName", ""))
        if pid in pids or any(fragment and fragment in owner for fragment in owners):
            result.append(window)
    result.sort(key=lambda item: (item["kCGWindowBounds"]["Width"] * item["kCGWindowBounds"]["Height"]), reverse=True)
    return result


def descendants(pid: int) -> set[int]:
    pids = {pid}
    changed = True
    while changed:
        changed = False
        output = subprocess.run(["ps", "-axo", "pid=,ppid="], text=True, capture_output=True).stdout
        for line in output.splitlines():
            parts = line.split()
            if len(parts) != 2:
                continue
            child, parent = map(int, parts)
            if parent in pids and child not in pids:
                pids.add(child)
                changed = True
    return pids


def capture_window(window_id: int, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["screencapture", "-x", "-l", str(window_id), str(output)], check=True)
    subprocess.run(["sips", "-s", "format", "png", str(output), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)


def launch_terminal(surface: Surface) -> int | None:
    close_terminal_window(all_windows=True)
    command = "cd " + shlex.quote(str(surface.cwd)) + " && "
    if surface.env:
        command += " ".join(f"{key}={shlex.quote(value)}" for key, value in surface.env.items()) + " "
    command += " ".join(shlex.quote(part) for part in surface.command)
    script = f'''
tell application "Terminal"
  activate
  set targetTab to do script {json.dumps(command)}
  set targetWindow to front window
  set bounds of targetWindow to {{0, 40, 1800, 1120}}
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True)
    time.sleep(surface.wait)
    candidates = visible_window_candidates(set(), ["Terminal"], include_offscreen=True)
    return int(candidates[0]["kCGWindowNumber"]) if candidates else None


def close_terminal_window(all_windows: bool = False) -> None:
    target = "every window" if all_windows else "front window"
    subprocess.run(
        ["osascript", "-e", f'tell application "Terminal" to close {target} saving no'],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def launch_process(surface: Surface) -> tuple[subprocess.Popen[str], int | None]:
    env = os.environ.copy()
    env.update(BASE_ENV)
    env.update(surface.env)
    process = subprocess.Popen(
        surface.command,
        cwd=surface.cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    deadline = time.monotonic() + max(surface.wait, 2.0)
    seen_output: list[str] = []
    window_id = None
    while time.monotonic() < deadline and window_id is None:
        if process.stdout:
            while True:
                try:
                    ready, _, _ = select.select([process.stdout], [], [], 0)
                    if not ready:
                        break
                    line = process.stdout.readline()
                    if not line:
                        break
                    seen_output.append(line.rstrip())
                except Exception:
                    break
        pids = descendants(process.pid) if process.poll() is None else {process.pid}
        candidates = visible_window_candidates(pids, surface.owners)
        if candidates:
            window_id = int(candidates[0]["kCGWindowNumber"])
            break
        time.sleep(0.2)
    if window_id is None and process.poll() is not None:
        print(f"{surface.name}: process exited before window. Output: {' | '.join(seen_output[-6:])}")
    return process, window_id


def terminate(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            print(f"warning: process {process.pid} did not exit after SIGKILL", file=sys.stderr)


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, **kwargs)


def booted_ios_simulator() -> str | None:
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "-j"], check=True).stdout)["devices"]
    fallback = None
    for runtimes in devices.values():
        for device in runtimes:
            if device.get("state") == "Booted":
                return device["udid"]
            name = device.get("name", "")
            if fallback is None and ("iPhone" in name or "iPad" in name) and device.get("isAvailable", True):
                fallback = device["udid"]
    if fallback:
        subprocess.run(["xcrun", "simctl", "boot", fallback], check=False)
        subprocess.run(["xcrun", "simctl", "bootstatus", fallback, "-b"], check=True)
    return fallback


def capture_ios(output: Path, wait: float) -> None:
    if not IOS_APP.exists():
        raise RuntimeError(f"missing iOS simulator app: {IOS_APP}; run make build PLATFORM=ios-simulator")
    simulator = booted_ios_simulator()
    if simulator is None:
        raise RuntimeError("no available iOS simulator")
    try:
        subprocess.run(["open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", simulator], check=False)
        subprocess.run(["xcrun", "simctl", "install", simulator, str(IOS_APP)], check=True)
        subprocess.run(["xcrun", "simctl", "launch", simulator, IOS_BUNDLE_ID], check=True)
        time.sleep(wait)
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "simctl", "io", simulator, "screenshot", str(output)], check=True)
    finally:
        subprocess.run(["xcrun", "simctl", "terminate", simulator, IOS_BUNDLE_ID], check=False)
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], check=False)


def adb() -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(Path.home() / "Library/Android/sdk")
    candidate = Path(sdk) / "platform-tools/adb"
    return str(candidate) if candidate.exists() else "adb"


def ensure_android_device() -> tuple[str, str | None, bool, subprocess.Popen[str] | None]:
    adb_path = adb()
    devices = run([adb_path, "devices"], check=True).stdout.splitlines()
    for line in devices[1:]:
        if "\tdevice" in line:
            serial = line.split("\t", 1)[0].strip()
            return adb_path, serial, serial.startswith("emulator-"), None

    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(Path.home() / "Library/Android/sdk")
    emulator_path = Path(sdk) / "emulator/emulator"
    emulator_command = str(emulator_path) if emulator_path.exists() else "emulator"
    avds = run([emulator_command, "-list-avds"], check=True).stdout.splitlines()
    if not avds:
        raise RuntimeError("no Android device is connected and no emulator AVDs are available")
    emulator = subprocess.Popen(
        [emulator_command, "-avd", avds[0], "-no-snapshot-save"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        subprocess.run([adb_path, "wait-for-device"], check=True)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            booted = run([adb_path, "shell", "getprop", "sys.boot_completed"], check=False).stdout.strip()
            if booted == "1":
                return adb_path, connected_android_serial(adb_path), True, emulator
            time.sleep(2)
        raise RuntimeError("timed out waiting for Android emulator to boot")
    except Exception:
        emulator.terminate()
        try:
            emulator.wait(timeout=5)
        except subprocess.TimeoutExpired:
            emulator.kill()
            emulator.wait()
        raise


def connected_android_serial(adb_path: str) -> str | None:
    devices = run([adb_path, "devices"], check=False).stdout.splitlines()
    for line in devices[1:]:
        if "\tdevice" in line:
            return line.split("\t", 1)[0].strip()
    return None


def adb_command(adb_path: str, serial: str | None, *parts: str) -> list[str]:
    command = [adb_path]
    if serial:
        command.extend(["-s", serial])
    command.extend(parts)
    return command


def capture_android(output: Path, wait: float) -> None:
    if not ANDROID_APK.exists():
        raise RuntimeError(f"missing Android APK: {ANDROID_APK}; run make build PLATFORM=android")
    adb_path, serial, shutdown_after_capture, emulator = ensure_android_device()
    try:
        subprocess.run(adb_command(adb_path, serial, "install", "-r", str(ANDROID_APK)), check=True)
        subprocess.run(adb_command(adb_path, serial, "shell", "am", "start", "-n", ANDROID_ACTIVITY), check=True)
        time.sleep(wait)
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("wb") as file:
            subprocess.run(adb_command(adb_path, serial, "exec-out", "screencap", "-p"), check=True, stdout=file)
    finally:
        subprocess.run(adb_command(adb_path, serial, "shell", "am", "force-stop", "dev.guiforcli.compose.android"), check=False)
        if shutdown_after_capture:
            subprocess.run(adb_command(adb_path, serial, "emu", "kill"), check=False)
            if emulator is not None:
                try:
                    emulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    emulator.terminate()
                    try:
                        emulator.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        emulator.kill()
                        emulator.wait(timeout=5)
            if serial:
                wait_for_android_disconnect(adb_path, serial, timeout=45)


def wait_for_android_disconnect(adb_path: str, serial: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        devices = run([adb_path, "devices"], check=False).stdout.splitlines()
        if all(not line.startswith(f"{serial}\t") for line in devices):
            return
        time.sleep(1)
    raise RuntimeError(f"Android emulator {serial} did not disconnect after screenshot capture")


def main() -> int:
    failures: list[str] = []
    only = {item.strip() for item in os.environ.get("CAPTURE_ONLY", "").split(",") if item.strip()}
    surfaces = [surface for surface in SURFACES if not only or surface.name in only]
    for surface in surfaces:
        output = OUT / f"{surface.name}.png"
        print(f"==> {surface.name}", flush=True)
        try:
            if surface.kind == "terminal":
                window_id = launch_terminal(surface)
                if window_id is None:
                    raise RuntimeError("no Terminal window found")
                capture_window(window_id, output)
                close_terminal_window()
            elif surface.kind == "ios":
                capture_ios(output, surface.wait)
            elif surface.kind == "android":
                capture_android(output, surface.wait)
            elif surface.kind == "command":
                subprocess.run(surface.command, cwd=surface.cwd, env={**os.environ, **BASE_ENV, **surface.env}, check=True)
            else:
                if not surface.command:
                    raise RuntimeError("missing command")
                process, window_id = launch_process(surface)
                try:
                    if window_id is None:
                        raise RuntimeError("no visible window found")
                    time.sleep(0.5)
                    capture_window(window_id, output)
                finally:
                    terminate(process)
            print(f"captured {output.relative_to(REPO)}", flush=True)
        except Exception as error:
            failures.append(f"{surface.name}: {error}")
            print(f"FAILED {surface.name}: {error}", flush=True)
            if surface.kind == "terminal":
                close_terminal_window()
    if failures:
        print("\nFailures:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
