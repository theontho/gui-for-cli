#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(CDPATH= cd "$script_dir/../.." && pwd)}"
runtime="$bundle_root/runtime/wgsextract-cli"

if [ -e "$runtime" ]; then
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "$runtime" 2>/dev/null || true
  fi
  rm -rf "$runtime"
fi
printf 'Removed WGS Extract runtime: %s\n' "$runtime"
