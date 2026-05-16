#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUI_WORKTREE_DIR="${GUI_WORKTREE_DIR:-$HOME/src/gui-worktree}"
FLUTTER_WORKTREE="${FLUTTER_WORKTREE:-$ROOT_DIR}"
SLINT_WORKTREE="${SLINT_WORKTREE:-$ROOT_DIR}"
SWIFTUI_APP="${SWIFTUI_APP:-$ROOT_DIR/platform/apple/DerivedData/Build/Products/Debug/GUI for CLI.app}"
SWIFTUI_EXE="${SWIFTUI_EXE:-$SWIFTUI_APP/Contents/MacOS/GUI for CLI}"
TAURI_APP="${TAURI_APP:-$ROOT_DIR/platform/typescript/web/packagers/tauri/target/release/bundle/macos/GUI for CLI WebUI.app}"
TAURI_EXE="${TAURI_EXE:-$TAURI_APP/Contents/MacOS/gui-for-cli-webui-tauri}"
FLUTTER_APP="${FLUTTER_APP:-$FLUTTER_WORKTREE/exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app}"
FLUTTER_EXE="${FLUTTER_EXE:-$FLUTTER_APP/Contents/MacOS/gui_for_cli_flutter}"
SLINT_BIN="${SLINT_BIN:-$SLINT_WORKTREE/exp-platform/rust/slint/target/release/gui-for-cli-slint}"
BUNDLE="${BUNDLE:-$ROOT_DIR/examples/WGSExtract}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/tmp/app-launch-logs}"
SWIFTUI_WINDOW_WIDTH="${SWIFTUI_WINDOW_WIDTH:-1120}"
SWIFTUI_WINDOW_HEIGHT="${SWIFTUI_WINDOW_HEIGHT:-720}"
TAURI_WINDOW_WIDTH="${TAURI_WINDOW_WIDTH:-1120}"
TAURI_WINDOW_HEIGHT="${TAURI_WINDOW_HEIGHT:-720}"
SLINT_WINDOW_WIDTH="${SLINT_WINDOW_WIDTH:-1120}"
SLINT_WINDOW_HEIGHT="${SLINT_WINDOW_HEIGHT:-720}"
FLUTTER_WINDOW_SCALE_PERCENT="${FLUTTER_WINDOW_SCALE_PERCENT:-120}"
QUIT_AFTER_SECONDS="${QUIT_AFTER_SECONDS:-3}"
DRY_RUN=0
POSITION_WINDOWS=0
REVERSE_ORDER=0
KEEP_OPEN=0
swiftui_pid=""
tauri_pid=""
flutter_pid=""
slint_pid=""
DEFAULT_ORDER=(swiftui tauri flutter slint)
REVERSE_ORDER_LIST=(slint flutter tauri swiftui)

usage() {
  cat <<'USAGE'
Usage: tools/experiments/launch_flutter_slint.sh [--dry-run] [--position] [--reverse] [--keep-open]

Launches the already-built SwiftUI, Tauri, Flutter, and Slint macOS apps immediately
one after another, so their visual startup timing can be compared.

By default the script launches SwiftUI, Tauri, Flutter, then Slint and leaves
windows wherever macOS opens them. Pass --position to arrange them in a 2x2
layout. Pass --reverse to launch/place Slint, Flutter, Tauri, then SwiftUI.
Unless --keep-open is passed, the script quits the launched app processes after
3 seconds.

Environment overrides:
  SWIFTUI_APP  Path to GUI for CLI.app
  SWIFTUI_EXE  Path to the SwiftUI executable inside SWIFTUI_APP
  TAURI_APP    Path to GUI for CLI WebUI.app
  TAURI_EXE    Path to the Tauri executable inside TAURI_APP
  GUI_WORKTREE_DIR
               Root directory containing PR worktrees (default ~/src/gui-worktree)
  FLUTTER_WORKTREE / SLINT_WORKTREE
               Worktree roots used for Flutter/Slint default build outputs
  FLUTTER_APP  Path to gui_for_cli_flutter.app
  FLUTTER_EXE  Path to the Flutter executable inside FLUTTER_APP
  SLINT_BIN    Path to gui-for-cli-slint
  BUNDLE       Bundle path passed to Slint
  LOG_DIR      Directory for launch logs
  SWIFTUI_WINDOW_WIDTH/HEIGHT
              Static SwiftUI window size in pixels (default 1120x720)
  TAURI_WINDOW_WIDTH/HEIGHT
              Static Tauri window size in pixels (default 1120x720)
  SLINT_WINDOW_WIDTH/HEIGHT
              Static Slint window size in pixels (default 1120x720)
  FLUTTER_WINDOW_SCALE_PERCENT
              Flutter window scale versus Slint (default 120)
  QUIT_AFTER_SECONDS
              Seconds to keep launched apps open (default 3)
USAGE
}

position_windows() {
  osascript - \
    "$slot1_pid" "$slot1_width" "$slot1_height" \
    "$slot2_pid" "$slot2_width" "$slot2_height" \
    "$slot3_pid" "$slot3_width" "$slot3_height" \
    "$slot4_pid" "$slot4_width" "$slot4_height" <<'APPLESCRIPT'
on run argv
  set slot1Pid to (item 1 of argv) as integer
  set slot1Width to (item 2 of argv) as integer
  set slot1Height to (item 3 of argv) as integer
  set slot2Pid to (item 4 of argv) as integer
  set slot2Width to (item 5 of argv) as integer
  set slot2Height to (item 6 of argv) as integer
  set slot3Pid to (item 7 of argv) as integer
  set slot3Width to (item 8 of argv) as integer
  set slot3Height to (item 9 of argv) as integer
  set slot4Pid to (item 10 of argv) as integer
  set slot4Width to (item 11 of argv) as integer
  set slot4Height to (item 12 of argv) as integer

  tell application "Finder"
    set desktopBounds to bounds of window of desktop
  end tell

  set screenLeft to item 1 of desktopBounds
  set screenTop to item 2 of desktopBounds
  set screenRight to item 3 of desktopBounds
  set screenBottom to item 4 of desktopBounds
  set screenWidth to screenRight - screenLeft
  set gutter to 16
  set topMargin to 48
  set leftColumnWidth to slot1Width
  if slot3Width > leftColumnWidth then set leftColumnWidth to slot3Width
  set rightColumnWidth to slot2Width
  if slot4Width > rightColumnWidth then set rightColumnWidth to slot4Width
  set topRowHeight to slot1Height
  if slot2Height > topRowHeight then set topRowHeight to slot2Height
  set totalWidth to leftColumnWidth + rightColumnWidth + gutter
  set leftX to screenLeft + ((screenWidth - totalWidth) div 2)
  if leftX < screenLeft then set leftX to screenLeft
  set rightX to leftX + leftColumnWidth + gutter
  if (rightX + rightColumnWidth) > screenRight then set rightX to screenRight - rightColumnWidth
  set windowTop to screenTop + topMargin
  set bottomTop to windowTop + topRowHeight + gutter
  if (bottomTop + slot3Height) > screenBottom then set bottomTop to screenBottom - slot3Height
  if bottomTop < windowTop then set bottomTop to windowTop

  set slot1Placed to placeWindow(slot1Pid, {leftX, windowTop}, {slot1Width, slot1Height})
  set slot2Placed to placeWindow(slot2Pid, {rightX, windowTop}, {slot2Width, slot2Height})
  set slot3Placed to placeWindow(slot3Pid, {leftX, bottomTop}, {slot3Width, slot3Height})
  set slot4Placed to placeWindow(slot4Pid, {rightX, bottomTop}, {slot4Width, slot4Height})

  if slot1Placed is false then error "First app window did not appear before the positioning timeout"
  if slot2Placed is false then error "Second app window did not appear before the positioning timeout"
  if slot3Placed is false then error "Third app window did not appear before the positioning timeout"
  if slot4Placed is false then error "Fourth app window did not appear before the positioning timeout"
end run

on placeWindow(processPid, newPosition, newSize)
  tell application "System Events"
    set deadline to (current date) + 8
    repeat while (current date) is less than deadline
      if exists (first process whose unix id is processPid) then
        tell (first process whose unix id is processPid)
          if (count of windows) > 0 then
            set position of window 1 to newPosition
            set size of window 1 to newSize
            return true
          end if
        end tell
      end if
      delay 0.05
    end repeat
  end tell
  return false
end placeWindow
APPLESCRIPT
}

require_integer() {
  local value="$1"
  local name="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer, got: %s\n' "$name" "$value" >&2
    exit 2
  fi
}

quit_pid() {
  local label="$1"
  local pid="$2"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    printf 'Quit %s PID %s.\n' "$label" "$pid"
  fi
}

start_on_gate() {
  local log_file="$1"
  shift
  nohup bash -c '
    gate="$1"
    shift
    while [[ ! -e "$gate" ]]; do
      sleep 0.001
    done
    exec "$@"
  ' bash "$launch_gate" "$@" >"$log_file" 2>&1 &
}

platform_swiftui() {
  local action="$1"
  local timestamp="${2:-}"
  case "$action" in
    label) printf 'SwiftUI\n' ;;
    width) printf '%s\n' "$SWIFTUI_WINDOW_WIDTH" ;;
    height) printf '%s\n' "$SWIFTUI_WINDOW_HEIGHT" ;;
    pid) printf '%s\n' "$swiftui_pid" ;;
    validate)
      require_path "$SWIFTUI_APP" "SwiftUI app"
      require_path "$SWIFTUI_EXE" "SwiftUI executable"
      ;;
    describe)
      printf 'SwiftUI app: %s\n' "$SWIFTUI_APP"
      printf 'SwiftUI executable: %s\n' "$SWIFTUI_EXE"
      ;;
    launch)
      swiftui_log="$LOG_DIR/swiftui-visual-$timestamp.log"
      start_on_gate "$swiftui_log" "$SWIFTUI_EXE"
      swiftui_pid=$!
      printf 'SwiftUI PID: %d\n' "$swiftui_pid"
      printf 'SwiftUI log: %s\n' "$swiftui_log"
      ;;
    quit)
      quit_pid "SwiftUI" "$swiftui_pid"
      ;;
    *)
      printf 'Unknown SwiftUI action: %s\n' "$action" >&2
      exit 2
      ;;
  esac
}

platform_tauri() {
  local action="$1"
  local timestamp="${2:-}"
  case "$action" in
    label) printf 'Tauri\n' ;;
    width) printf '%s\n' "$TAURI_WINDOW_WIDTH" ;;
    height) printf '%s\n' "$TAURI_WINDOW_HEIGHT" ;;
    pid) printf '%s\n' "$tauri_pid" ;;
    validate)
      require_path "$TAURI_APP" "Tauri app"
      require_path "$TAURI_EXE" "Tauri executable"
      ;;
    describe)
      printf 'Tauri app: %s\n' "$TAURI_APP"
      printf 'Tauri executable: %s\n' "$TAURI_EXE"
      ;;
    launch)
      tauri_log="$LOG_DIR/tauri-visual-$timestamp.log"
      start_on_gate "$tauri_log" "$TAURI_EXE"
      tauri_pid=$!
      printf 'Tauri PID: %d\n' "$tauri_pid"
      printf 'Tauri log: %s\n' "$tauri_log"
      ;;
    quit)
      quit_pid "Tauri" "$tauri_pid"
      ;;
    *)
      printf 'Unknown Tauri action: %s\n' "$action" >&2
      exit 2
      ;;
  esac
}

platform_flutter() {
  local action="$1"
  local timestamp="${2:-}"
  case "$action" in
    label) printf 'Flutter\n' ;;
    width) printf '%s\n' "$flutter_width" ;;
    height) printf '%s\n' "$flutter_height" ;;
    pid) printf '%s\n' "$flutter_pid" ;;
    validate)
      require_path "$FLUTTER_APP" "Flutter app"
      require_path "$FLUTTER_EXE" "Flutter executable"
      ;;
    describe)
      printf 'Flutter app: %s\n' "$FLUTTER_APP"
      printf 'Flutter executable: %s\n' "$FLUTTER_EXE"
      ;;
    launch)
      flutter_log="$LOG_DIR/flutter-visual-$timestamp.log"
      start_on_gate "$flutter_log" "$FLUTTER_EXE"
      flutter_pid=$!
      printf 'Flutter PID: %d\n' "$flutter_pid"
      printf 'Flutter log: %s\n' "$flutter_log"
      ;;
    quit)
      quit_pid "Flutter" "$flutter_pid"
      ;;
    *)
      printf 'Unknown Flutter action: %s\n' "$action" >&2
      exit 2
      ;;
  esac
}

platform_slint() {
  local action="$1"
  local timestamp="${2:-}"
  case "$action" in
    label) printf 'Slint\n' ;;
    width) printf '%s\n' "$SLINT_WINDOW_WIDTH" ;;
    height) printf '%s\n' "$SLINT_WINDOW_HEIGHT" ;;
    pid) printf '%s\n' "$slint_pid" ;;
    validate)
      require_path "$SLINT_BIN" "Slint binary"
      require_path "$BUNDLE" "bundle"
      ;;
    describe)
      printf 'Slint binary: %s\n' "$SLINT_BIN"
      printf 'Bundle: %s\n' "$BUNDLE"
      ;;
    launch)
      slint_log="$LOG_DIR/slint-visual-$timestamp.log"
      start_on_gate "$slint_log" "$SLINT_BIN" --bundle "$BUNDLE"
      slint_pid=$!
      printf 'Slint PID: %d\n' "$slint_pid"
      printf 'Slint log: %s\n' "$slint_log"
      ;;
    quit)
      quit_pid "Slint" "$slint_pid"
      ;;
    *)
      printf 'Unknown Slint action: %s\n' "$action" >&2
      exit 2
      ;;
  esac
}

platform() {
  local app="$1"
  local action="$2"
  local timestamp="${3:-}"
  case "$app" in
    swiftui) platform_swiftui "$action" "$timestamp" ;;
    tauri) platform_tauri "$action" "$timestamp" ;;
    flutter) platform_flutter "$action" "$timestamp" ;;
    slint) platform_slint "$action" "$timestamp" ;;
    *)
      printf 'Unknown platform: %s\n' "$app" >&2
      exit 2
      ;;
  esac
}

for argument in "$@"; do
  case "$argument" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-position)
      POSITION_WINDOWS=0
      ;;
    --position)
      POSITION_WINDOWS=1
      ;;
    --reverse)
      REVERSE_ORDER=1
      ;;
    --keep-open)
      KEEP_OPEN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$argument" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_path() {
  local path="$1"
  local hint="$2"
  if [[ ! -e "$path" ]]; then
    printf 'Missing %s: %s\n' "$hint" "$path" >&2
    printf 'Build first with: make flutter-build build-slint\n' >&2
    exit 1
  fi
}

require_integer "$SWIFTUI_WINDOW_WIDTH" "SWIFTUI_WINDOW_WIDTH"
require_integer "$SWIFTUI_WINDOW_HEIGHT" "SWIFTUI_WINDOW_HEIGHT"
require_integer "$TAURI_WINDOW_WIDTH" "TAURI_WINDOW_WIDTH"
require_integer "$TAURI_WINDOW_HEIGHT" "TAURI_WINDOW_HEIGHT"
require_integer "$SLINT_WINDOW_WIDTH" "SLINT_WINDOW_WIDTH"
require_integer "$SLINT_WINDOW_HEIGHT" "SLINT_WINDOW_HEIGHT"
require_integer "$FLUTTER_WINDOW_SCALE_PERCENT" "FLUTTER_WINDOW_SCALE_PERCENT"
require_integer "$QUIT_AFTER_SECONDS" "QUIT_AFTER_SECONDS"
if [[ "$REVERSE_ORDER" == 1 ]]; then
  order=("${REVERSE_ORDER_LIST[@]}")
else
  order=("${DEFAULT_ORDER[@]}")
fi

mkdir -p "$LOG_DIR"

flutter_width=$(( SLINT_WINDOW_WIDTH * FLUTTER_WINDOW_SCALE_PERCENT / 100 ))
flutter_height=$(( SLINT_WINDOW_HEIGHT * FLUTTER_WINDOW_SCALE_PERCENT / 100 ))

for app in "${order[@]}"; do
  platform "$app" describe
done
printf 'Window sizes: SwiftUI %sx%s px, Tauri %sx%s px, Flutter %sx%s px (%s%% of Slint), Slint %sx%s px\n' "$SWIFTUI_WINDOW_WIDTH" "$SWIFTUI_WINDOW_HEIGHT" "$TAURI_WINDOW_WIDTH" "$TAURI_WINDOW_HEIGHT" "$flutter_width" "$flutter_height" "$FLUTTER_WINDOW_SCALE_PERCENT" "$SLINT_WINDOW_WIDTH" "$SLINT_WINDOW_HEIGHT"
if [[ "$KEEP_OPEN" == 1 ]]; then
  printf 'Quit behavior: disabled (--keep-open).\n'
else
  printf 'Quit behavior: quit launched apps after %s seconds.\n' "$QUIT_AFTER_SECONDS"
fi
printf 'Launch order: %s -> %s -> %s -> %s\n' "$(platform "${order[0]}" label)" "$(platform "${order[1]}" label)" "$(platform "${order[2]}" label)" "$(platform "${order[3]}" label)"

if [[ "$DRY_RUN" == 1 ]]; then
  printf 'Dry run only; nothing launched.\n'
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
for app in "${order[@]}"; do
  platform "$app" validate
done

launch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gui-for-cli-launch.XXXXXX")"
launch_gate="$launch_dir/go"
trap 'rm -rf "$launch_dir"' EXIT
for app in "${order[@]}"; do
  platform "$app" launch "$timestamp"
done
touch "$launch_gate"

slot1_pid="$(platform "${order[0]}" pid)"
slot2_pid="$(platform "${order[1]}" pid)"
slot3_pid="$(platform "${order[2]}" pid)"
slot4_pid="$(platform "${order[3]}" pid)"
slot1_width="$(platform "${order[0]}" width)"; slot1_height="$(platform "${order[0]}" height)"
slot2_width="$(platform "${order[1]}" width)"; slot2_height="$(platform "${order[1]}" height)"
slot3_width="$(platform "${order[2]}" width)"; slot3_height="$(platform "${order[2]}" height)"
slot4_width="$(platform "${order[3]}" width)"; slot4_height="$(platform "${order[3]}" height)"

if [[ "$POSITION_WINDOWS" == 0 ]]; then
  printf 'Window positioning disabled.\n'
elif position_windows; then
  printf 'Positioned %s upper-left, %s upper-right, %s lower-left, and %s lower-right.\n' "$(platform "${order[0]}" label)" "$(platform "${order[1]}" label)" "$(platform "${order[2]}" label)" "$(platform "${order[3]}" label)"
else
  printf 'Could not position windows automatically. Enable Accessibility permission for your terminal if macOS blocked System Events.\n' >&2
fi

if [[ "$KEEP_OPEN" == 0 ]]; then
  sleep "$QUIT_AFTER_SECONDS"
  for app in "${order[@]}"; do
    platform "$app" quit
  done
fi
