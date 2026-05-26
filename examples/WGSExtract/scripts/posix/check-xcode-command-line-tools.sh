#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' "Xcode Command Line Tools are only required on macOS."
  exit 0
fi

tools_ready() {
  /usr/bin/xcode-select -p >/dev/null 2>&1
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

find_command_line_tools_label() {
  /usr/sbin/softwareupdate --list 2>&1 |
    /usr/bin/awk '
      /\* Label: Command Line Tools/ {
        sub(/^.*Label: /, "")
        print
      }
      /\* Command Line Tools/ {
        sub(/^.*\* /, "")
        print
      }
    ' |
    /usr/bin/tail -n 1
}

install_marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
/usr/bin/touch "$install_marker"
trap '/bin/rm -f "$install_marker"' EXIT

label="$(find_command_line_tools_label)"
if [ -n "$label" ]; then
  printf 'Installing Xcode Command Line Tools package: %s\n' "$label"
  /usr/sbin/softwareupdate --install "$label" --verbose
else
  printf '%s\n' "No softwareupdate package was listed; falling back to the macOS installer dialog."
  if /usr/bin/xcode-select --install >/dev/null 2>&1; then
    printf '%s\n' "Requested Xcode Command Line Tools installation."
  else
    printf '%s\n' "The installer dialog may already be open, or macOS could not open it automatically."
  fi
fi

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
