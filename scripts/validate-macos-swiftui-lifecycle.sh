#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-macos-swiftui-lifecycle.sh [options]

Build, clean-install, launch, auto-run setup, uninstall bundle runtime, and
remove installed app data for the SwiftUI macOS WGSExtract app. Designed for
repeatable install/setup/uninstall cycles without pressing "Start Setup".

For long edit/rerun loops that may span multiple failed script invocations,
run scripts/macos-sudo-session.sh start once, then use --admin-mode
sudo-noprompt until scripts/macos-sudo-session.sh stop.

Options:
  --cycles N          Number of lifecycle cycles. Default: 1
  --state-root PATH   Working/log directory. Default: tmp/macos-swiftui-lifecycle
  --install-dir PATH  App install directory. Default: <state-root>/Applications
  --setup-timeout N   Seconds to wait for setup completion. Default: 1800
  --startup-timeout N Seconds to wait for app startup marker. Default: 60
  --admin-mode MODE   Admin authorization mode: sudo-once or sudo-noprompt.
                      Default: sudo-once
  --skip-build        Reuse the existing Debug WGSExtract.app build.
  --keep              Keep state-root after success.
  -h, --help          Show this help.

Outputs per cycle:
  cycle-*/terminal.log       GUI for CLI terminal stream
  cycle-*/setup-result.json  Final setup run state
  cycle-*/stdout.log         App stdout
  cycle-*/stderr.log         App stderr
  summary.jsonl              Machine-readable JSON Lines stage summary
EOF
}

log() { printf '[macos-swiftui-lifecycle] %s\n' "$*"; }
fail() { printf '[macos-swiftui-lifecycle] error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cycles=1
state_root="$repo_root/tmp/macos-swiftui-lifecycle"
install_dir=""
setup_timeout=1800
startup_timeout=60
admin_mode="${GUI_FOR_CLI_MACOS_LIFECYCLE_ADMIN_MODE:-sudo-once}"
skip_build=0
keep=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cycles) [ "$#" -ge 2 ] || fail "Missing --cycles value."; cycles="$2"; shift 2 ;;
    --state-root) [ "$#" -ge 2 ] || fail "Missing --state-root value."; state_root="$2"; shift 2 ;;
    --install-dir) [ "$#" -ge 2 ] || fail "Missing --install-dir value."; install_dir="$2"; shift 2 ;;
    --setup-timeout) [ "$#" -ge 2 ] || fail "Missing --setup-timeout value."; setup_timeout="$2"; shift 2 ;;
    --startup-timeout) [ "$#" -ge 2 ] || fail "Missing --startup-timeout value."; startup_timeout="$2"; shift 2 ;;
    --admin-mode) [ "$#" -ge 2 ] || fail "Missing --admin-mode value."; admin_mode="$2"; shift 2 ;;
    --skip-build) skip_build=1; shift ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || fail "This script only runs on macOS."
case "$cycles:$setup_timeout:$startup_timeout" in
  *[!0-9:]* | :* | *::*) fail "--cycles and timeouts must be positive integers." ;;
esac
[ "$cycles" -gt 0 ] || fail "--cycles must be greater than 0."
case "$admin_mode" in
  sudo-once | sudo-noprompt) ;;
  *) fail "--admin-mode must be sudo-once or sudo-noprompt." ;;
esac

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}
require_command ditto
require_command osascript
require_command python3
require_command sudo

state_root="$(mkdir -p "$state_root" && cd "$state_root" && pwd)"
case "$state_root" in
  / | "$HOME" | "$repo_root" | "$repo_root"/platform | "$repo_root"/examples)
    fail "Refusing unsafe --state-root: $state_root"
    ;;
esac
install_dir="${install_dir:-$state_root/Applications}"
summary_path="$state_root/summary.jsonl"
: > "$summary_path"

app_build="$repo_root/platform/apple/DerivedData/Build/Products/Debug/WGSExtract.app"
bundle_id="dev.guiforcli.embed.wgsextract"
admin_keepalive_pid=""
sudo_askpass_path=""

json_event() {
  local cycle="$1" stage="$2" status="$3" detail="${4:-}"
  python3 - "$summary_path" "$cycle" "$stage" "$status" "$detail" <<'PY'
import json, sys, time
path, cycle, stage, status, detail = sys.argv[1:]
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps({
        "time": time.time(),
        "cycle": int(cycle),
        "stage": stage,
        "status": status,
        "detail": detail,
    }, sort_keys=True) + "\n")
PY
}

stage() {
  local cycle="$1" name="$2"
  shift 2
  log "cycle $cycle: $name"
  json_event "$cycle" "$name" "start"
  local started=$SECONDS
  if "$@"; then
    json_event "$cycle" "$name" "ok" "$((SECONDS - started))s"
  else
    local code=$?
    json_event "$cycle" "$name" "failed" "exit=$code after $((SECONDS - started))s"
    return "$code"
  fi
}

processes_for_cycle() {
  local app_path="$1" support_name="$2"
  ps ax -o pid= -o command= | awk \
    -v app="$app_path/Contents/MacOS/" \
    -v support="$support_name" \
    '{
      command = $0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", command)
      if (command ~ /^awk[[:space:]]/) { next }
      if (index($0, app) || index($0, support)) { print $1 }
    }'
}

stop_processes_for_cycle() {
  local app_path="$1" support_name="$2" deadline pid
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  deadline=$((SECONDS + 10))
  while [ "$SECONDS" -lt "$deadline" ]; do
    [ -z "$(processes_for_cycle "$app_path" "$support_name")" ] && return 0
    sleep 1
  done
  for pid in $(processes_for_cycle "$app_path" "$support_name"); do
    [ "$pid" != "$$" ] && kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 2
  for pid in $(processes_for_cycle "$app_path" "$support_name"); do
    [ "$pid" != "$$" ] && kill -9 "$pid" >/dev/null 2>&1 || true
  done
  [ -z "$(processes_for_cycle "$app_path" "$support_name")" ] || return 1
}

cleanup_cycle_data() {
  local cycle_dir="$1" app_path="$2" support_name="$3"
  cleanup_installed_app_and_data "$app_path" "$support_name"
  rm -rf "$cycle_dir"
  mkdir -p "$cycle_dir" "$install_dir"
}

cleanup_installed_app_and_data() {
  local app_path="$1" support_name="$2"
  local support_dir="$HOME/Library/Application Support/$support_name"
  stop_processes_for_cycle "$app_path" "$support_name" || true
  rm -rf "$app_path" "$support_dir"
  rm -rf "$HOME/Library/Caches/$support_name" \
    "$HOME/Library/Logs/$support_name" \
    "$HOME/Library/Saved Application State/$bundle_id.savedState"
}

build_app() {
  if [ "$skip_build" -eq 1 ]; then
    [ -d "$app_build" ] || fail "Missing built app: $app_build"
    return 0
  fi
  (cd "$repo_root" && make setup PLATFORM=apple-project && make build PLATFORM=swiftui-macos)
  [ -d "$app_build" ] || fail "Build did not create $app_build"
}

install_app() {
  local app_path="$1"
  rm -rf "$app_path"
  ditto "$app_build" "$app_path"
  [ -x "$app_path/Contents/MacOS/WGSExtract" ]
}

start_app() {
  local app_path="$1" support_name="$2" cycle_dir="$3"
  local stdout_log="$cycle_dir/stdout.log" stderr_log="$cycle_dir/stderr.log"
  : > "$stdout_log"
  : > "$stderr_log"
  env \
    GUI_FOR_CLI_APP_SUPPORT_NAME="$support_name" \
    GUI_FOR_CLI_AUTO_RUN_SETUP=1 \
    GUI_FOR_CLI_TERMINAL_LOG_FILE="$cycle_dir/terminal.log" \
    GUI_FOR_CLI_SETUP_RESULT_FILE="$cycle_dir/setup-result.json" \
    GUI_FOR_CLI_MACOS_ADMIN_MODE=sudo-noprompt \
    GFC_BENCHMARK_OUTPUT="$cycle_dir/startup.log" \
    "$app_path/Contents/MacOS/WGSExtract" \
    --benchmark-output "$cycle_dir/startup.log" \
    >"$stdout_log" 2>"$stderr_log" &
  echo "$!" > "$cycle_dir/app.pid"
}

wait_for_startup() {
  local cycle_dir="$1" deadline=$((SECONDS + startup_timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -s "$cycle_dir/startup.log" ] && grep -q 'content_initialized' "$cycle_dir/startup.log"; then
      return 0
    fi
    if [ -f "$cycle_dir/app.pid" ] && ! kill -0 "$(cat "$cycle_dir/app.pid")" 2>/dev/null; then
      fail "App exited during startup. See $cycle_dir/stderr.log"
    fi
    sleep 1
  done
  fail "Timed out waiting for startup marker. See $cycle_dir/stdout.log and $cycle_dir/stderr.log"
}

wait_for_setup() {
  local cycle_dir="$1" deadline=$((SECONDS + setup_timeout))
  local result="$cycle_dir/setup-result.json"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -s "$result" ]; then
      if ! python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
failed = [step for step in result.get("results", []) if step.get("status") not in ("ok", "warning")]
if result.get("status") != "ok" or failed:
    print(json.dumps(result, indent=2, sort_keys=True))
    sys.exit(1)
PY
      then
        fail "Setup failed. See $cycle_dir/setup-result.json and $cycle_dir/terminal.log"
      fi
      return 0
    fi
    if [ -f "$cycle_dir/app.pid" ] && ! kill -0 "$(cat "$cycle_dir/app.pid")" 2>/dev/null; then
      fail "App exited before setup completed. See $cycle_dir/terminal.log and $cycle_dir/stderr.log"
    fi
    sleep 2
  done
  tail -80 "$cycle_dir/terminal.log" 2>/dev/null || true
  fail "Timed out waiting for setup result: $result"
}

bundle_workspace() {
  local support_name="$1"
  printf '%s\n' "$HOME/Library/Application Support/$support_name/BundleWorkspaces/wgs-extract"
}

uninstall_bundle_runtime() {
  local support_name="$1"
  local workspace
  workspace="$(bundle_workspace "$support_name")"
  [ -d "$workspace" ] || fail "Missing bundle workspace: $workspace"
  GUI_FOR_CLI_BUNDLE_WORKSPACE="$workspace" "$workspace/scripts/posix/uninstall-wgsextract.sh"
  [ ! -e "$workspace/runtime/wgsextract-cli" ] || fail "Runtime remained after uninstall: $workspace/runtime/wgsextract-cli"
}

assert_cleaned() {
  local app_path="$1" support_name="$2"
  local support_dir="$HOME/Library/Application Support/$support_name"
  [ ! -e "$app_path" ] || fail "Installed app remained: $app_path"
  [ ! -e "$support_dir" ] || fail "App support remained: $support_dir"
}

start_sudo_keepalive() {
  (
    while true; do
      sudo -n -v >/dev/null 2>&1 || exit 0
      sleep 45
    done
  ) &
  admin_keepalive_pid="$!"
}

start_admin_session() {
  if [ "$admin_mode" = "sudo-once" ]; then
    log "requesting sudo once for automated setup/uninstall lifecycle steps"
    if sudo -n true >/dev/null 2>&1; then
      :
    elif [ -t 0 ]; then
      sudo -v
    else
      sudo_askpass_path="$state_root/sudo-askpass.sh"
      cat >"$sudo_askpass_path" <<'ASKPASS'
#!/usr/bin/env bash
/usr/bin/osascript <<'OSA'
display dialog "GUI for CLI needs administrator privileges for the automated macOS lifecycle test." default answer "" with hidden answer buttons {"OK"} default button "OK"
text returned of result
OSA
ASKPASS
      chmod 700 "$sudo_askpass_path"
      SUDO_ASKPASS="$sudo_askpass_path" sudo -A -v
    fi
    start_sudo_keepalive
    log "sudo authorization is active; keeping it warm for lifecycle cycles"
    return
  fi

  if sudo -n true >/dev/null 2>&1; then
    start_sudo_keepalive
    log "noninteractive sudo is available; keeping authorization warm for admin-mode test steps"
  else
    log "noninteractive sudo is not available; admin-mode steps will fail fast instead of prompting"
  fi
}

cleanup() {
  if [ -n "$admin_keepalive_pid" ] && kill -0 "$admin_keepalive_pid" 2>/dev/null; then
    kill "$admin_keepalive_pid" >/dev/null 2>&1 || true
    wait "$admin_keepalive_pid" 2>/dev/null || true
  fi
  if [ -n "$sudo_askpass_path" ]; then
    rm -f "$sudo_askpass_path"
  fi
}
trap cleanup EXIT INT HUP TERM

build_app
start_admin_session

for cycle in $(seq 1 "$cycles"); do
  cycle_dir="$state_root/cycle-$cycle"
  app_path="$install_dir/WGSExtract.app"
  support_name="dev.guiforcli.lifecycle.$cycle"
  stage "$cycle" "clean-before-install" cleanup_cycle_data "$cycle_dir" "$app_path" "$support_name"
  stage "$cycle" "install-app" install_app "$app_path"
  stage "$cycle" "launch-auto-setup" start_app "$app_path" "$support_name" "$cycle_dir"
  stage "$cycle" "wait-for-startup" wait_for_startup "$cycle_dir"
  stage "$cycle" "wait-for-setup" wait_for_setup "$cycle_dir"
  stage "$cycle" "bundle-runtime-uninstall" uninstall_bundle_runtime "$support_name"
  stage "$cycle" "quit-app" stop_processes_for_cycle "$app_path" "$support_name"
  stage "$cycle" "clean-installed-app-and-data" cleanup_installed_app_and_data "$app_path" "$support_name"
  stage "$cycle" "assert-clean" assert_cleaned "$app_path" "$support_name"
done

log "summary: $summary_path"
if [ "$keep" -eq 1 ]; then
  log "keeping logs for inspection in $state_root"
else
  rm -rf "$state_root"
  log "removed lifecycle state root after success; rerun with --keep to preserve logs"
fi
