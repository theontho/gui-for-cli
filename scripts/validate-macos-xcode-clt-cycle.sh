#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-macos-xcode-clt-cycle.sh [options]

Exercise the WGSExtract "Verify or install Xcode Command Line Tools" setup
step while avoiding repeated full Xcode downloads. The script moves the full
Xcode app into a local cache, removes Command Line Tools, runs the setup
installer script, verifies CLT availability, then restores and selects Xcode.

Options:
  --xcode-app PATH       Xcode app to cache/restore.
                         Default: auto-detect from xcode-select or /Applications.
  --cache-dir PATH       Directory used while Xcode is "uninstalled".
                         Default: ~/Library/Caches/gui-for-cli/xcode-app-cache
  --setup-script PATH    CLT check/install script to run.
                         Default: examples/WGSExtract/scripts/posix/check-xcode-command-line-tools.sh
  --timeout SECONDS      Timeout passed to the CLT installer script.
                         Default: 1800
  --state-root PATH      Directory for test logs.
                         Default: tmp/macos-xcode-clt-cycle
  --admin-mode MODE      Admin authorization mode: osascript-once, sudo-once,
                         osascript, or root. Default: osascript-once
  --leave-xcode-cached   Leave Xcode in the cache instead of restoring it.
  -h, --help             Show this help.

Notes:
  - This still downloads/reinstalls Command Line Tools when macOS requires it.
  - The full Xcode app is cached by moving it, so restoring Xcode is fast.
  - osascript-once asks for administrator authorization once, then runs the
    entire cycle in one elevated worker process.
EOF
}

log() { printf '[xcode-clt-cycle] %s\n' "$*"; }
fail() { printf '[xcode-clt-cycle] error: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

shell_quote() {
  local value
  value="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$value"
}

detect_xcode_app() {
  local developer_dir app candidate
  developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  case "$developer_dir" in
    /Applications/*.app/Contents/Developer)
      app="${developer_dir%/Contents/Developer}"
      if [ -d "$app" ]; then printf '%s\n' "$app"; return; fi
      ;;
  esac
  if [ -d /Applications/Xcode.app ]; then
    printf '%s\n' /Applications/Xcode.app
    return
  fi
  candidate="$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' | sort | tail -n 1)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
  fi
}

run_admin() {
  local prompt="$1"
  local script="$2"
  case "$admin_mode" in
    sudo-once)
      SUDO_ASKPASS="${sudo_askpass_path:-}" sudo -A /bin/sh -c "$script"
      ;;
    osascript)
      /usr/bin/osascript - "$script" "$prompt" <<'OSA'
on run argv
  do shell script item 1 of argv with administrator privileges with prompt item 2 of argv
end run
OSA
      ;;
    root)
      /bin/sh -c "$script"
      ;;
    *)
      fail "Unsupported admin mode: $admin_mode"
      ;;
  esac
}

sudo_keepalive_pid=""
sudo_askpass_path=""

start_sudo_session() {
  [ "$admin_mode" = "sudo-once" ] || return 0
  log "Requesting sudo once for the full CLT cycle."
  if [ -t 0 ]; then
    sudo -v
  else
    sudo_askpass_path="$state_root/sudo-askpass.sh"
    cat >"$sudo_askpass_path" <<'ASKPASS'
#!/usr/bin/env bash
/usr/bin/osascript <<'OSA'
display dialog "GUI for CLI needs administrator privileges for the Xcode Command Line Tools cycle test." default answer "" with hidden answer buttons {"OK"} default button "OK"
text returned of result
OSA
ASKPASS
    chmod 700 "$sudo_askpass_path"
    SUDO_ASKPASS="$sudo_askpass_path" sudo -A -v
  fi
  (
    while true; do
      sleep 60
      sudo -n -v >/dev/null 2>&1 || exit 0
    done
  ) &
  sudo_keepalive_pid="$!"
}

stop_sudo_session() {
  if [ -n "$sudo_keepalive_pid" ]; then
    kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
    wait "$sudo_keepalive_pid" 2>/dev/null || true
    sudo_keepalive_pid=""
  fi
  if [ -n "$sudo_askpass_path" ]; then
    rm -f "$sudo_askpass_path"
    sudo_askpass_path=""
  fi
}

script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcode_app=""
cache_dir="$HOME/Library/Caches/gui-for-cli/xcode-app-cache"
setup_script="$repo_root/examples/WGSExtract/scripts/posix/check-xcode-command-line-tools.sh"
timeout_seconds=1800
state_root="$repo_root/tmp/macos-xcode-clt-cycle"
restore_xcode_on_exit=1
admin_mode="${ADMIN_MODE:-osascript-once}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --xcode-app)
      [ "$#" -ge 2 ] || fail "Missing value for --xcode-app."
      xcode_app="$2"
      shift 2
      ;;
    --cache-dir)
      [ "$#" -ge 2 ] || fail "Missing value for --cache-dir."
      cache_dir="$2"
      shift 2
      ;;
    --setup-script)
      [ "$#" -ge 2 ] || fail "Missing value for --setup-script."
      setup_script="$2"
      shift 2
      ;;
    --timeout)
      [ "$#" -ge 2 ] || fail "Missing value for --timeout."
      timeout_seconds="$2"
      shift 2
      ;;
    --state-root)
      [ "$#" -ge 2 ] || fail "Missing value for --state-root."
      state_root="$2"
      shift 2
      ;;
    --admin-mode)
      [ "$#" -ge 2 ] || fail "Missing value for --admin-mode."
      admin_mode="$2"
      shift 2
      ;;
    --leave-xcode-cached)
      restore_xcode_on_exit=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || fail "This test only runs on macOS."
case "$timeout_seconds" in
  '' | *[!0-9]*) fail "--timeout must be an integer number of seconds." ;;
esac

require_command osascript
require_command sed
require_command tee
if [ "$admin_mode" = "sudo-once" ]; then
  require_command sudo
elif [ "$admin_mode" != "osascript" ] && [ "$admin_mode" != "osascript-once" ] && [ "$admin_mode" != "root" ]; then
  fail "--admin-mode must be osascript-once, sudo-once, osascript, or root."
fi

setup_script="$(cd "$(dirname "$setup_script")" && pwd)/$(basename "$setup_script")"
[ -f "$setup_script" ] || fail "Setup script not found: $setup_script"
xcode_app="${xcode_app:-$(detect_xcode_app)}"
[ -n "$xcode_app" ] || fail "Could not detect Xcode. Pass --xcode-app PATH."

state_root="$(mkdir -p "$state_root" && cd "$state_root" && pwd)"
setup_log="$state_root/clt-install-output.log"
summary_log="$state_root/summary.log"
root_log="$state_root/root-cycle-output.log"
root_runner="$state_root/root-cycle-runner.sh"
cached_xcode="$cache_dir/$(basename "$xcode_app")"
xcode_parent_dir="$(dirname "$xcode_app")"
quoted_xcode_app="$(shell_quote "$xcode_app")"
quoted_xcode_developer="$(shell_quote "$xcode_app/Contents/Developer")"
quoted_cache_dir="$(shell_quote "$cache_dir")"
quoted_cached_xcode="$(shell_quote "$cached_xcode")"
quoted_xcode_parent_dir="$(shell_quote "$xcode_parent_dir")"

if [ "$admin_mode" = "osascript-once" ] && [ "$(/usr/bin/id -u)" -eq 0 ]; then
  admin_mode="root"
fi

if [ "$admin_mode" = "osascript-once" ] && [ "$(/usr/bin/id -u)" -ne 0 ]; then
  log "Requesting administrator authorization once for the full CLT cycle."
  : >"$root_log"
  leave_xcode_cached_arg=""
  if [ "$restore_xcode_on_exit" -eq 0 ]; then
    leave_xcode_cached_arg="--leave-xcode-cached"
  fi
  cat >"$root_runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec $(shell_quote "$script_path") \\
  --xcode-app $(shell_quote "$xcode_app") \\
  --cache-dir $(shell_quote "$cache_dir") \\
  --setup-script $(shell_quote "$setup_script") \\
  --timeout $(shell_quote "$timeout_seconds") \\
  --state-root $(shell_quote "$state_root") \\
  --admin-mode root \\
  $leave_xcode_cached_arg
EOF
  chmod 700 "$root_runner"
  /usr/bin/osascript - "$root_runner" "$root_log" <<'OSA' &
on run argv
  set runnerPath to item 1 of argv
  set logPath to item 2 of argv
  do shell script quoted form of runnerPath & " > " & quoted form of logPath & " 2>&1" with administrator privileges with prompt "GUI for CLI needs administrator privileges once to run the full Xcode Command Line Tools cycle test."
end run
OSA
  osascript_pid="$!"
  tail -f "$root_log" &
  tail_pid="$!"
  wait "$osascript_pid"
  osascript_status="$?"
  sleep 1
  kill "$tail_pid" >/dev/null 2>&1 || true
  wait "$tail_pid" 2>/dev/null || true
  exit "$osascript_status"
fi

restored=0

restore_xcode() {
  if [ "$restore_xcode_on_exit" -ne 1 ] || [ "$restored" -eq 1 ]; then
    return
  fi
  if [ -d "$xcode_app" ]; then
    log "Selecting restored Xcode at $xcode_app"
    run_admin \
      "GUI for CLI needs administrator privileges to select the restored Xcode after CLT cycle testing." \
      "/usr/bin/xcode-select --switch $quoted_xcode_developer" >/dev/null
    restored=1
    return
  fi
  if [ -d "$cached_xcode" ]; then
    log "Restoring cached Xcode to $xcode_app"
    run_admin \
      "GUI for CLI needs administrator privileges to restore cached Xcode after CLT cycle testing." \
      "/bin/mkdir -p $quoted_xcode_parent_dir; /bin/mv $quoted_cached_xcode $quoted_xcode_app; /usr/bin/xcode-select --switch $quoted_xcode_developer" >/dev/null
    restored=1
  fi
}

cleanup() {
  restore_xcode || true
  stop_sudo_session
}
trap cleanup EXIT INT HUP TERM

log "Writing logs to $state_root"
start_sudo_session

if [ -d "$xcode_app" ] && [ -d "$cached_xcode" ]; then
  fail "Both Xcode app and cache exist; refusing to choose one: $xcode_app and $cached_xcode"
fi

if [ ! -d "$xcode_app" ] && [ ! -d "$cached_xcode" ]; then
  fail "Neither Xcode app nor cache exists. Install Xcode once first: $xcode_app"
fi

if [ -d "$xcode_app" ]; then
  log "Caching Xcode by moving $xcode_app to $cached_xcode"
  run_admin \
    "GUI for CLI needs administrator privileges to move Xcode into a cache for CLT cycle testing." \
    "/bin/mkdir -p $quoted_cache_dir; /bin/mv $quoted_xcode_app $quoted_cached_xcode" >/dev/null
else
  log "Using already cached Xcode at $cached_xcode"
fi

log "Removing Command Line Tools and resetting xcode-select"
run_admin \
  "GUI for CLI needs administrator privileges to remove Xcode Command Line Tools for CLT installer testing." \
  "/bin/rm -rf /Library/Developer/CommandLineTools; /usr/bin/xcode-select --reset >/dev/null 2>&1 || true" >/dev/null

if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  fail "xcode-select still reports a developer directory after removal: $(/usr/bin/xcode-select -p)"
fi
log "Verified developer tools are unavailable before installer run."

log "Running setup script to verify/install Xcode Command Line Tools"
installer_script="cd $(shell_quote "$repo_root") && XCODE_SELECT_INSTALL_TIMEOUT_SECONDS=$(shell_quote "$timeout_seconds") /bin/sh $(shell_quote "$setup_script")"
if run_admin \
  "GUI for CLI needs administrator privileges to test installing Xcode Command Line Tools." \
  "$installer_script" | tee "$setup_log"; then
  log "Setup script completed."
else
  fail "Setup script failed. See $setup_log"
fi

developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
if [ -z "$developer_dir" ]; then
  fail "xcode-select still has no developer directory after setup. See $setup_log"
fi
if [ ! -d "$developer_dir" ]; then
  fail "xcode-select points to a missing developer directory after setup: $developer_dir"
fi
log "CLT installer result: xcode-select now points to $developer_dir"

restore_xcode

final_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
{
  printf 'setup_script=%s\n' "$setup_script"
  printf 'setup_log=%s\n' "$setup_log"
  printf 'clt_developer_dir=%s\n' "$developer_dir"
  printf 'restored_xcode=%s\n' "$xcode_app"
  printf 'final_developer_dir=%s\n' "$final_developer_dir"
} >"$summary_log"
log "Summary written to $summary_log"
log "Done."
