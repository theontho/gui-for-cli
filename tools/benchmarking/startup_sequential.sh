#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI_WORKTREE_DIR="${GUI_WORKTREE_DIR:-$HOME/src/gui-worktree}"
FLUTTER_WORKTREE="${FLUTTER_WORKTREE:-$ROOT_DIR}"
SLINT_WORKTREE="${SLINT_WORKTREE:-$ROOT_DIR}"
GIO_WORKTREE="${GIO_WORKTREE:-$ROOT_DIR}"
RN_WORKTREE="${RN_WORKTREE:-$GUI_WORKTREE_DIR/pr-24-add-react-native-version}"
SWIFTUI_APP="${SWIFTUI_APP:-$ROOT_DIR/platform/apple/DerivedData/Build/Products/Debug/GUI for CLI.app}"
SWIFTUI_EXE="${SWIFTUI_EXE:-$SWIFTUI_APP/Contents/MacOS/GUI for CLI}"
TAURI_APP="${TAURI_APP:-$ROOT_DIR/platform/typescript/web/packagers/tauri/target/release/bundle/macos/GUI for CLI WebUI.app}"
TAURI_EXE="${TAURI_EXE:-$TAURI_APP/Contents/MacOS/gui-for-cli-webui-tauri}"
FLUTTER_APP="${FLUTTER_APP:-$FLUTTER_WORKTREE/exp-platform/dart/flutter/build/macos/Build/Products/Release/gui_for_cli_flutter.app}"
FLUTTER_EXE="${FLUTTER_EXE:-$FLUTTER_APP/Contents/MacOS/gui_for_cli_flutter}"
SLINT_BIN="${SLINT_BIN:-$SLINT_WORKTREE/exp-platform/rust/slint/target/release/gui-for-cli-slint}"
GIO_BIN="${GIO_BIN:-$GIO_WORKTREE/out/release/gio/gui-for-cli-gio}"
RN_APP="${RN_APP:-$RN_WORKTREE/Apps/ReactNative/GUIForCLIReactNative/macos/build/Build/Products/Release/GUIForCLIReactNative.app}"
RN_EXE="${RN_EXE:-$RN_APP/Contents/MacOS/GUIForCLIReactNative}"
BUNDLE="${BUNDLE:-$ROOT_DIR/examples/WGSExtract}"
BUILTIN_STRINGS="${BUILTIN_STRINGS:-$ROOT_DIR/resources/BuiltinStrings}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/tmp/sequential-startup-logs}"
STARTUP_HOLD_SECONDS="${STARTUP_HOLD_SECONDS:-2}"
STARTUP_BETWEEN_SECONDS="${STARTUP_BETWEEN_SECONDS:-0.5}"
DRY_RUN=0
REVERSE_ORDER=0
DEFAULT_ORDER=(swiftui tauri flutter slint)
REVERSE_ORDER_LIST=(slint flutter tauri swiftui)
order=()

usage() {
  cat <<'USAGE'
Usage: tools/benchmarking/startup_sequential.sh [--dry-run] [--reverse] [--apps swiftui,tauri,flutter,slint,gio,rn]

Starts each selected app one at a time, sleeps 2 seconds, kills that app,
sleeps 0.5 seconds, then starts the next app until the list is complete.

Default order is SwiftUI, Tauri, Flutter, Slint. Pass --reverse to run Slint,
Flutter, Tauri, SwiftUI. Gio and React Native can be included with --apps.

Environment overrides:
  SWIFTUI_APP / SWIFTUI_EXE
  TAURI_APP / TAURI_EXE
  GUI_WORKTREE_DIR
  FLUTTER_WORKTREE / SLINT_WORKTREE / GIO_WORKTREE / RN_WORKTREE
  FLUTTER_APP / FLUTTER_EXE
  SLINT_BIN
  GIO_BIN
  RN_APP / RN_EXE
  BUNDLE / BUILTIN_STRINGS
  LOG_DIR
  STARTUP_HOLD_SECONDS     Seconds to keep each app running (default 2)
  STARTUP_BETWEEN_SECONDS  Seconds between apps after kill (default 0.5)
USAGE
}

require_seconds() {
  local value="$1"
  local name="$2"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s must be a non-negative number, got: %s\n' "$name" "$value" >&2
    exit 2
  fi
}

require_path() {
  local path="$1"
  local hint="$2"
  if [[ ! -e "$path" ]]; then
    printf 'Missing %s: %s\n' "$hint" "$path" >&2
    printf 'Build first with: make build-macos build-webui-tauri flutter-build build-slint\n' >&2
    exit 1
  fi
}

label_for() {
  case "$1" in
    swiftui) printf 'SwiftUI\n' ;;
    tauri) printf 'Tauri\n' ;;
    flutter) printf 'Flutter\n' ;;
    slint) printf 'Slint\n' ;;
    gio) printf 'Gio\n' ;;
    rn|react-native) printf 'React Native\n' ;;
    *)
      printf 'Unknown platform: %s\n' "$1" >&2
      exit 2
      ;;
  esac
}

validate_app() {
  case "$1" in
    swiftui)
      require_path "$SWIFTUI_APP" "SwiftUI app"
      require_path "$SWIFTUI_EXE" "SwiftUI executable"
      ;;
    tauri)
      require_path "$TAURI_APP" "Tauri app"
      require_path "$TAURI_EXE" "Tauri executable"
      ;;
    flutter)
      require_path "$FLUTTER_APP" "Flutter app"
      require_path "$FLUTTER_EXE" "Flutter executable"
      ;;
    slint)
      require_path "$SLINT_BIN" "Slint binary"
      require_path "$BUNDLE" "bundle"
      ;;
    gio)
      require_path "$GIO_BIN" "Gio binary"
      require_path "$BUNDLE" "bundle"
      require_path "$BUILTIN_STRINGS" "built-in strings"
      ;;
    rn|react-native)
      require_path "$RN_APP" "React Native macOS app"
      require_path "$RN_EXE" "React Native macOS executable"
      ;;
    *)
      label_for "$1" >/dev/null
      ;;
  esac
}

describe_app() {
  case "$1" in
    swiftui)
      printf 'SwiftUI executable: %s\n' "$SWIFTUI_EXE"
      ;;
    tauri)
      printf 'Tauri executable: %s\n' "$TAURI_EXE"
      ;;
    flutter)
      printf 'Flutter executable: %s\n' "$FLUTTER_EXE"
      ;;
    slint)
      printf 'Slint binary: %s\n' "$SLINT_BIN"
      printf 'Bundle: %s\n' "$BUNDLE"
      ;;
    gio)
      printf 'Gio binary: %s\n' "$GIO_BIN"
      printf 'Bundle: %s\n' "$BUNDLE"
      ;;
    rn|react-native)
      printf 'React Native executable: %s\n' "$RN_EXE"
      ;;
    *)
      label_for "$1" >/dev/null
      ;;
  esac
}

launch_app() {
  local app="$1"
  local log_file="$2"
  case "$app" in
    swiftui)
      nohup "$SWIFTUI_EXE" >"$log_file" 2>&1 &
      ;;
    tauri)
      nohup "$TAURI_EXE" >"$log_file" 2>&1 &
      ;;
    flutter)
      nohup "$FLUTTER_EXE" >"$log_file" 2>&1 &
      ;;
    slint)
      nohup "$SLINT_BIN" --bundle "$BUNDLE" >"$log_file" 2>&1 &
      ;;
    gio)
      nohup env \
        GFC_GIO_REPO_ROOT="$ROOT_DIR" \
        GFC_GIO_BUNDLE="$BUNDLE" \
        GFC_GIO_BUILTIN_STRINGS="$BUILTIN_STRINGS" \
        "$GIO_BIN" >"$log_file" 2>&1 &
      ;;
    rn|react-native)
      nohup "$RN_EXE" >"$log_file" 2>&1 &
      ;;
    *)
      label_for "$app" >/dev/null
      ;;
  esac
  printf '%s\n' "$!"
}

terminate_app() {
  local label="$1"
  local pid="$2"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf '[%s] killed PID %s after %ss.\n' "$label" "$pid" "$STARTUP_HOLD_SECONDS"
  else
    printf '[%s] PID %s exited before the %ss hold finished.\n' "$label" "$pid" "$STARTUP_HOLD_SECONDS"
  fi
}

parse_apps() {
  local value="$1"
  local old_ifs="$IFS"
  IFS=,
  read -r -a order <<<"$value"
  IFS="$old_ifs"
  if [[ "${#order[@]}" -eq 0 ]]; then
    printf '%s\n' '--apps must include at least one platform.' >&2
    exit 2
  fi
}

shell_quote() {
  if [[ "$1" =~ ^[A-Za-z0-9_./:,@%+=-]+$ ]]; then
    printf '%s' "$1"
  else
    printf '%q' "$1"
  fi
}

joined_order() {
  local old_ifs="$IFS"
  IFS=,
  printf '%s' "${order[*]}"
  IFS="$old_ifs"
}

print_copy_paste_command() {
  printf 'Copy/paste launch command: '
  printf 'STARTUP_HOLD_SECONDS=%s ' "$(shell_quote "$STARTUP_HOLD_SECONDS")"
  printf 'STARTUP_BETWEEN_SECONDS=%s ' "$(shell_quote "$STARTUP_BETWEEN_SECONDS")"
  printf 'tools/benchmarking/startup_sequential.sh --apps %s\n' "$(shell_quote "$(joined_order)")"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --reverse)
      REVERSE_ORDER=1
      shift
      ;;
    --apps)
      if [[ "$#" -lt 2 ]]; then
        printf '%s\n' '--apps requires a comma-separated platform list.' >&2
        exit 2
      fi
      parse_apps "$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${#order[@]}" -eq 0 ]]; then
  if [[ "$REVERSE_ORDER" == 1 ]]; then
    order=("${REVERSE_ORDER_LIST[@]}")
  else
    order=("${DEFAULT_ORDER[@]}")
  fi
fi

require_seconds "$STARTUP_HOLD_SECONDS" "STARTUP_HOLD_SECONDS"
require_seconds "$STARTUP_BETWEEN_SECONDS" "STARTUP_BETWEEN_SECONDS"

for app in "${order[@]}"; do
  label_for "$app" >/dev/null
done

printf 'Sequential startup measurement order:'
for app in "${order[@]}"; do
  printf ' %s' "$(label_for "$app")"
done
printf '\n'
printf 'Hold: %ss; between apps: %ss; logs: %s\n' "$STARTUP_HOLD_SECONDS" "$STARTUP_BETWEEN_SECONDS" "$LOG_DIR"
print_copy_paste_command

for app in "${order[@]}"; do
  describe_app "$app"
done

if [[ "$DRY_RUN" == 1 ]]; then
  printf 'Dry run only; nothing launched.\n'
  exit 0
fi

mkdir -p "$LOG_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

for app in "${order[@]}"; do
  validate_app "$app"
done

for app in "${order[@]}"; do
  label="$(label_for "$app")"
  log_file="$LOG_DIR/${app}-${timestamp}.log"
  printf '[%s] starting...\n' "$label"
  pid="$(launch_app "$app" "$log_file")"
  printf '[%s] PID %s; log: %s\n' "$label" "$pid" "$log_file"
  sleep "$STARTUP_HOLD_SECONDS"
  terminate_app "$label" "$pid"
  sleep "$STARTUP_BETWEEN_SECONDS"
done

printf 'Sequential startup measurement complete.\n'
