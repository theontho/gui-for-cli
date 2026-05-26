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
macOS may show a system dialog titled "Install Command Line Developer Tools".
Approve that dialog and wait for the installation to finish; this setup step will keep checking.
EOF

if /usr/bin/xcode-select --install >/dev/null 2>&1; then
  printf '%s\n' "Requested Xcode Command Line Tools installation."
else
  printf '%s\n' "The installer dialog may already be open, or macOS could not open it automatically."
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
