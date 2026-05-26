from __future__ import annotations

import json
import signal
import subprocess
import time
from pathlib import Path

try:
    from .macos_update_common import bundle_version, read_info_plist, run
except ImportError:  # pragma: no cover - script execution path
    from macos_update_common import bundle_version, read_info_plist, run


def run_update_flow(
    *,
    surface: str,
    app: Path,
    expected_version: str,
    old_version: str,
    menu: tuple[str, str],
    buttons: tuple[str, ...],
    work_dir: Path,
    record: bool,
    video_seconds: int,
    hold_seconds: float,
    prompt_hold_seconds: float,
) -> Path | None:
    video = work_dir / "videos" / f"{surface}-update.mov" if record else None
    if record:
        assert video is not None
        video.parent.mkdir(parents=True, exist_ok=True)
        video.unlink(missing_ok=True)
    process_name = app.stem
    stop_running_app(process_name)
    register_app_bundle(app)
    recorder = start_recording(video, video_seconds) if record else None
    try:
        run(["open", "-n", str(app)])
        old_pid = wait_for_process(process_name)
        wait_for_visible_version(process_name, old_version, timeout=30)
        time.sleep(hold_seconds)
        click_update_menu(process_name, menu[0], menu[1])
        time.sleep(prompt_hold_seconds)
        drive_update_until_version(
            app,
            expected_version,
            process_name,
            old_pid,
            buttons,
            timeout=video_seconds,
            relaunch_app=app if surface == "swiftui" else None,
        )
        wait_for_visible_version(process_name, expected_version, timeout=45)
        time.sleep(hold_seconds)
    finally:
        stop_running_app(process_name)
        if recorder is not None:
            finish_recording(recorder, video, video_seconds)
    return video


def click_update_menu(process_name: str, menu_name: str, item_name: str) -> None:
    process = applescript_string(process_name)
    menu = applescript_string(menu_name)
    item = applescript_string(item_name)
    script = f"""
tell application {process} to activate
tell application "System Events"
  tell process {process}
    set frontmost to true
    delay 0.5
    tell menu bar 1
      click menu bar item {menu}
      delay 0.3
      if not (enabled of menu item {item} of menu 1 of menu bar item {menu}) then error "Update menu item is disabled"
      click menu item {item} of menu 1 of menu bar item {menu}
    end tell
  end tell
end tell
"""
    run(["osascript", "-e", script])


def drive_update_until_version(
    app: Path,
    expected_version: str,
    process_name: str,
    old_pid: int,
    button_names: tuple[str, ...],
    timeout: int,
    relaunch_app: Path | None,
) -> None:
    deadline = time.monotonic() + timeout
    process = applescript_string(process_name)
    quoted = ", ".join(applescript_string(name) for name in button_names)
    script = f"""
set targetButtons to {{{quoted}}}
tell application "System Events"
  tell process {process}
    repeat with buttonName in targetButtons
      try
        click (first button of entire contents whose name is (buttonName as text))
        return true
      end try
    end repeat
  end tell
end tell
return false
"""
    last_state_log = 0.0
    while time.monotonic() < deadline:
        if bundle_version(app) == expected_version and process_pid(process_name) not in (0, old_pid):
            return
        if bundle_version(app) == expected_version and relaunch_app is not None:
            relaunch_updated_app(process_name, old_pid, relaunch_app)
            return
        result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
        if result.stdout.strip() == "true" and bundle_version(app) == expected_version:
            if relaunch_app is not None:
                relaunch_updated_app(process_name, old_pid, relaunch_app)
            else:
                wait_for_process_exit(old_pid, timeout=30)
                wait_for_new_process(process_name, old_pid, timeout=45)
            return
        now = time.monotonic()
        if now - last_state_log > 10:
            print(update_ui_state(process_name))
            last_state_log = now
        subprocess.run(["osascript", "-e", 'tell application "System Events" to key code 36'], check=False)
        time.sleep(1)
    actual = bundle_version(app) if app.exists() else "<missing>"
    raise TimeoutError(f"{process_name} did not update to {expected_version}; current version is {actual}.")


def relaunch_updated_app(process_name: str, old_pid: int, app: Path) -> None:
    subprocess.run(["osascript", "-e", f"tell application {applescript_string(process_name)} to quit"], check=False)
    wait_for_process_exit(old_pid, timeout=30)
    run(["open", "-n", str(app)])
    wait_for_new_process(process_name, old_pid, timeout=45)


def update_ui_state(process_name: str) -> str:
    process = applescript_string(process_name)
    script = f"""
tell application "System Events"
  if not (exists process {process}) then return "process missing"
  tell process {process}
    set output to "windows: " & (name of every window as text)
    repeat with appWindow in windows
      try
        set output to output & " | " & (name of appWindow as text) & " buttons: " & (name of every button of appWindow as text)
      end try
    end repeat
    return output
  end tell
end tell
"""
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    return result.stdout.strip() or result.stderr.strip()


def wait_for_visible_version(process_name: str, version: str, timeout: int) -> None:
    target = f"{version}"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ui_contains_text(process_name, target):
            return
        time.sleep(0.5)
    print(f"Warning: {process_name} did not expose version {version} through Accessibility; continuing after bundle version verification.")


def ui_contains_text(process_name: str, target: str) -> bool:
    process = applescript_string(process_name)
    script = f"""
set targetText to {applescript_string(target)}
tell application "System Events"
  if not (exists process {process}) then return false
  tell process {process}
    try
      if (name of front window as text) contains targetText then return true
    end try
    repeat with uiElement in entire contents
      try
        if (value of uiElement as text) contains targetText then return true
      end try
      try
        if (name of uiElement as text) contains targetText then return true
      end try
      try
        if (description of uiElement as text) contains targetText then return true
      end try
    end repeat
  end tell
end tell
return false
"""
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    return result.stdout.strip() == "true"


def start_recording(video: Path, seconds: int) -> subprocess.Popen:
    del seconds
    return subprocess.Popen(["screencapture", "-v", "-k", str(video)])


def finish_recording(process: subprocess.Popen, video: Path, seconds: int) -> None:
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
    process.wait(timeout=seconds + 30)
    if process.returncode not in (0, -signal.SIGINT):
        raise RuntimeError(f"screencapture exited with code {process.returncode}.")
    if not video.exists() or video.stat().st_size == 0:
        raise RuntimeError(f"screencapture did not write a usable video at {video}.")


def applescript_string(value: str) -> str:
    return json.dumps(value)


def wait_for_process(process_name: str, timeout: int = 30) -> int:
    deadline = time.monotonic() + timeout
    process = applescript_string(process_name)
    script = f"""
tell application "System Events"
  if not (exists process {process}) then return false
  tell process {process}
    if (count of menu bars) = 0 then return false
    return unix id
  end tell
end tell
"""
    while time.monotonic() < deadline:
        result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
        output = result.stdout.strip()
        if output.isdigit() and int(output) > 0:
            time.sleep(2)
            return int(output)
        time.sleep(0.5)
    raise TimeoutError(f"{process_name} did not launch.")


def process_pid(process_name: str) -> int:
    process = applescript_string(process_name)
    script = f"""
tell application "System Events"
  if not (exists process {process}) then return 0
  tell process {process} to return unix id
end tell
"""
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    output = result.stdout.strip()
    return int(output) if output.isdigit() else 0


def wait_for_process_exit(pid: int, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.5)
    raise TimeoutError(f"Old app process {pid} did not quit.")


def wait_for_new_process(process_name: str, old_pid: int, timeout: int) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pid = process_pid(process_name)
        if pid and pid != old_pid:
            wait_for_process(process_name, timeout=10)
            return pid
        time.sleep(0.5)
    raise TimeoutError(f"{process_name} did not relaunch after update.")


def process_exists(pid: int) -> bool:
    if pid <= 0:
        return False
    return subprocess.run(["kill", "-0", str(pid)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def stop_running_app(process_name: str) -> None:
    subprocess.run(["osascript", "-e", f"tell application {applescript_string(process_name)} to quit"], check=False)
    time.sleep(1)
    pid = process_pid(process_name)
    if pid:
        terminate_process(pid, timeout=10)


def terminate_process(pid: int, timeout: int) -> None:
    subprocess.run(["kill", "-TERM", str(pid)], check=False)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.5)
    print(f"Warning: process {pid} did not exit after SIGTERM; sending SIGKILL.")
    subprocess.run(["kill", "-KILL", str(pid)], check=False)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.25)
    print(f"Warning: process {pid} is still visible after SIGKILL.")


def register_app_bundle(app: Path) -> None:
    lsregister = Path(
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    )
    if lsregister.exists():
        run([str(lsregister), "-f", str(app)])
