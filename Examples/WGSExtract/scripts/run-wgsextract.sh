#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="$(CDPATH= cd "$script_dir/.." && pwd)"
app_dir="${WGSEXTRACT_APP_DIR:-$bundle_root/runtime/wgsextract-cli/app}"

if [ -n "${PIXI:-}" ] && [ -x "$PIXI" ] && [ -d "$app_dir" ]; then
  cd "$app_dir"
  exec "$PIXI" run wgsextract "$@"
fi

if [ -d "$app_dir" ] && command -v pixi >/dev/null 2>&1; then
  cd "$app_dir"
  exec pixi run wgsextract "$@"
fi

if [ -d "$app_dir" ] && [ -x "$HOME/.pixi/bin/pixi" ]; then
  cd "$app_dir"
  exec "$HOME/.pixi/bin/pixi" run wgsextract "$@"
fi

if command -v wgsextract >/dev/null 2>&1; then
  exec wgsextract "$@"
fi

printf 'Error: WGS Extract CLI was not found. Run bundle setup first or install wgsextract on PATH.\n' >&2
exit 127
