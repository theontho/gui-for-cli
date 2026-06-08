#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/macos-sudo-session.sh <start|stop|status|refresh> [options]

Keep sudo authorization warm across repeated macOS validation runs. Start this
once before an edit/rerun loop, run lifecycle scripts in sudo-noprompt mode, and
stop it when finished.

Commands:
  start              Ask for sudo if needed, then start a long-lived keepalive.
  stop               Stop the keepalive process started by this helper.
  status             Report whether the keepalive process is running.
  refresh            Refresh the sudo timestamp; fails if the session is gone.

Options:
  --state-root PATH  Directory for session files.
                     Default: tmp/macos-sudo-session
  --reason TEXT      Prompt shown by the non-TTY password dialog.
  -h, --help         Show this help.

Example:
  scripts/macos-sudo-session.sh start
  scripts/validate-macos-swiftui-lifecycle.sh --admin-mode sudo-noprompt --cycles 1 --keep
  # edit, rebuild, and rerun without another password prompt
  scripts/macos-sudo-session.sh stop
EOF
}

log() { printf '[macos-sudo-session] %s\n' "$*"; }
fail() { printf '[macos-sudo-session] error: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

read_pid() {
  [ -f "$pid_file" ] || return 1
  local pid
  IFS= read -r pid <"$pid_file" || return 1
  case "$pid" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$pid"
}

keepalive_running() {
  local pid command
  pid="$(read_pid)" || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  command="$(ps -ww -p "$pid" -o args= 2>/dev/null || ps -ww -p "$pid" -o command= 2>/dev/null || true)"
  case "$command" in
    *"$keepalive_script"*) return 0 ;;
    *) return 1 ;;
  esac
}

canonical_state_root() {
  local path="$1" parent name parent_abs
  [ -n "$path" ] || fail "Refusing unsafe --state-root: $path"
  if [ -d "$path" ]; then
    (cd "$path" && pwd)
    return
  fi

  parent="$(dirname "$path")"
  name="$(basename "$path")"
  case "$name" in
    '' | . | ..) fail "Refusing unsafe --state-root: $path" ;;
  esac
  parent_abs="$(mkdir -p "$parent" && cd "$parent" && pwd)"
  printf '%s/%s\n' "$parent_abs" "$name"
}

refuse_unsafe_state_root() {
  case "$1" in
    '' | / | "$HOME" | "$repo_root" | "$repo_root"/platform | "$repo_root"/examples)
      fail "Refusing unsafe --state-root: $1"
      ;;
  esac
}

write_askpass() {
  ( umask 077; cat >"$askpass_path" <<'ASKPASS'
#!/usr/bin/env bash
prompt="${GUI_FOR_CLI_SUDO_SESSION_REASON:-GUI for CLI needs administrator privileges for repeated macOS validation.}"
exec /usr/bin/osascript - "$prompt" <<'OSA'
on run argv
  display dialog item 1 of argv default answer "" with hidden answer buttons {"OK"} default button "OK"
  text returned of result
end run
OSA
ASKPASS
)
  chmod 700 "$askpass_path"
}

authenticate_once() {
  if sudo -n -v >/dev/null 2>&1; then
    return
  fi

  if [ -t 0 ]; then
    sudo -v
  else
    write_askpass
    GUI_FOR_CLI_SUDO_SESSION_REASON="$reason" SUDO_ASKPASS="$askpass_path" sudo -A -v
  fi
}

write_keepalive() {
  cat >"$keepalive_script" <<'KEEPALIVE'
#!/usr/bin/env bash
set -euo pipefail

while true; do
  /usr/bin/sudo -n -v
  sleep 45
done
KEEPALIVE
  chmod 700 "$keepalive_script"
}

start_session() {
  if keepalive_running; then
    local pid
    pid="$(read_pid)"
    if sudo -n -v >/dev/null 2>&1; then
      log "session already active; keepalive pid=$pid"
      return
    fi
    log "keepalive pid=$pid is running, but sudo authorization is no longer valid; restarting session"
    stop_session
  fi

  authenticate_once
  write_keepalive
  : >"$log_path"
  /usr/bin/nohup "$keepalive_script" >>"$log_path" 2>&1 &
  printf '%s\n' "$!" >"$pid_file"
  log "session active; keepalive pid=$(cat "$pid_file")"
  log "run lifecycle validators with --admin-mode sudo-noprompt while iterating"
}

stop_session() {
  local pid
  if ! keepalive_running; then
    rm -f "$pid_file" "$askpass_path" "$keepalive_script"
    log "no active session"
    return
  fi

  pid="$(read_pid)"
  kill "$pid" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    keepalive_running || break
    sleep 1
  done
  if keepalive_running; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pid_file" "$askpass_path" "$keepalive_script"
  log "stopped keepalive pid=$pid"
}

status_session() {
  local pid
  if keepalive_running; then
    pid="$(read_pid)"
    if sudo -n -v >/dev/null 2>&1; then
      log "active; keepalive pid=$pid"
      return
    fi
    fail "keepalive pid=$pid is running, but sudo authorization is no longer valid"
  fi
  fail "no active session"
}

refresh_session() {
  local pid
  keepalive_running || fail "no active session"
  pid="$(read_pid)"
  if ! sudo -n -v >/dev/null 2>&1; then
    fail "keepalive pid=$pid is running, but sudo authorization is no longer valid; run start to authenticate again"
  fi
  log "refreshed sudo timestamp for keepalive pid=$pid"
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-}"
state_root="$repo_root/tmp/macos-sudo-session"
reason="GUI for CLI needs administrator privileges for repeated macOS lifecycle validation."

case "$action" in
  start | stop | status | refresh)
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  '')
    usage
    exit 2
    ;;
  *)
    fail "Unknown command: $action"
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-root)
      [ "$#" -ge 2 ] || fail "Missing --state-root value."
      state_root="$2"
      shift 2
      ;;
    --reason)
      [ "$#" -ge 2 ] || fail "Missing --reason value."
      reason="$2"
      shift 2
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

[ "$(uname -s)" = "Darwin" ] || fail "This helper only runs on macOS."
require_command osascript
require_command ps
require_command sudo

state_root="$(canonical_state_root "$state_root")"
refuse_unsafe_state_root "$state_root"
mkdir -p "$state_root"
pid_file="$state_root/keepalive.pid"
askpass_path="$state_root/sudo-askpass.sh"
keepalive_script="$state_root/keepalive.sh"
log_path="$state_root/keepalive.log"

case "$action" in
  start) start_session ;;
  stop) stop_session ;;
  status) status_session ;;
  refresh) refresh_session ;;
esac
