#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' "Xcode Command Line Tools are only required on macOS."
  exit 0
fi

tools_ready() {
  /usr/bin/xcode-select -p >/dev/null 2>&1
}

run_logged() {
  log_file="$1"
  description="$2"
  max_wait_seconds="$3"
  shift 3
  : >"$log_file"
  "$@" >"$log_file" 2>&1 &
  command_pid=$!
  elapsed_seconds=0
  while /bin/kill -0 "$command_pid" >/dev/null 2>&1; do
    sleep 10
    elapsed_seconds=$((elapsed_seconds + 10))
    printf 'Still %s (%s seconds elapsed)...\n' "$description" "$elapsed_seconds"
    /usr/bin/tail -n 5 "$log_file" | /usr/bin/sed 's/^/[softwareupdate] /'
    if [ "$elapsed_seconds" -ge "$max_wait_seconds" ]; then
      /bin/kill "$command_pid" >/dev/null 2>&1 || true
      sleep 5
      /bin/kill -0 "$command_pid" >/dev/null 2>&1 && /bin/kill -9 "$command_pid" >/dev/null 2>&1 || true
      wait "$command_pid" >/dev/null 2>&1 || true
      /bin/cat "$log_file"
      printf 'Timed out while %s after %s seconds.\n' "$description" "$elapsed_seconds" >&2
      return 124
    fi
  done
  command_status=0
  wait "$command_pid" || command_status=$?
  /bin/cat "$log_file"
  return "$command_status"
}

if tools_ready; then
  developer_dir="$(/usr/bin/xcode-select -p)"
  printf 'Xcode Command Line Tools are installed: %s\n' "$developer_dir"
  exit 0
fi

cat <<'EOF'
Xcode Command Line Tools are required before WGS Extract setup can continue.
macOS may ask for an administrator password before installing them.
EOF

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  cat >&2 <<'EOF'
Administrative privileges are required to install Xcode Command Line Tools.
Run this setup step from GUI for CLI or rerun the script with sudo.
EOF
  exit 1
fi

install_marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
/usr/bin/touch "$install_marker"

list_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/wgsextract-clt-list.XXXXXX.log")"
install_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/wgsextract-clt-install.XXXXXX.log")"
/bin/chmod 600 "$list_log" "$install_log"
cleanup_logs() {
  /bin/rm -f "$list_log" "$install_log"
}
trap 'cleanup_logs; /bin/rm -f "$install_marker"' EXIT
printf '%s\n' "Checking Apple's Software Update catalog for Xcode Command Line Tools..."
if run_logged "$list_log" "checking Apple's Software Update catalog" "${SOFTWAREUPDATE_LIST_TIMEOUT_SECONDS:-900}" /usr/sbin/softwareupdate --list; then
  label="$(
    /usr/bin/awk '
      /\* Label: Command Line Tools/ {
        sub(/^.*Label: /, "")
        print
      }
      /\* Command Line Tools/ {
        sub(/^.*\* /, "")
        print
      }
    ' "$list_log" |
      /usr/bin/tail -n 1
  )"
else
  label=""
fi

if [ -n "$label" ]; then
  printf 'Installing Xcode Command Line Tools package: %s\n' "$label"
  if ! run_logged "$install_log" "installing Xcode Command Line Tools" "${SOFTWAREUPDATE_INSTALL_TIMEOUT_SECONDS:-1800}" \
    /usr/sbin/softwareupdate --install "$label" --verbose; then
    cat >&2 <<'EOF'
Failed to install Xcode Command Line Tools with softwareupdate.
Check the softwareupdate output above, then rerun setup.
EOF
    exit 1
  fi
else
  printf '%s\n' "No softwareupdate package was listed; falling back to the macOS installer dialog."
  if /usr/bin/xcode-select --install >/dev/null 2>&1; then
    printf '%s\n' "Requested Xcode Command Line Tools installation."
  else
    printf '%s\n' "The installer dialog may already be open, or macOS could not open it automatically."
  fi
fi

printf '%s\n' "Waiting for Xcode Command Line Tools to become available..."
timeout_seconds="${XCODE_SELECT_INSTALL_TIMEOUT_SECONDS:-1800}"
elapsed_seconds=0
while [ "$elapsed_seconds" -lt "$timeout_seconds" ]; do
  if tools_ready; then
    developer_dir="$(/usr/bin/xcode-select -p)"
    printf 'Xcode Command Line Tools are installed: %s\n' "$developer_dir"
    exit 0
  fi
  sleep 5
  elapsed_seconds=$((elapsed_seconds + 5))
  if [ $((elapsed_seconds % 60)) -eq 0 ]; then
    printf 'Still waiting for Xcode Command Line Tools installation (%s seconds elapsed)...\n' "$elapsed_seconds"
  fi
done

cat >&2 <<'EOF'
Timed out waiting for Xcode Command Line Tools.
Finish the macOS installer dialog or run `xcode-select --install`, then rerun setup.
EOF
exit 1
