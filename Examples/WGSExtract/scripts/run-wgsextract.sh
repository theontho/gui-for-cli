#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="$(CDPATH= cd "$script_dir/.." && pwd)"
app_dir="${WGSEXTRACT_APP_DIR:-$bundle_root/runtime/wgsextract-cli/app}"
pixi=""

if [ ! -d "$app_dir" ]; then
  if [ "${WGSEXTRACT_ALLOW_PATH_FALLBACK:-0}" = "1" ] && command -v wgsextract >/dev/null 2>&1; then
    exec wgsextract "$@"
  fi
  printf 'Error: WGS Extract bundle runtime is not installed at %s.\n' "$app_dir" >&2
  printf 'Run the WGS Extract setup action before running commands.\n' >&2
  exit 127
fi

if [ -n "${PIXI:-}" ] && [ -x "$PIXI" ]; then
  pixi="$PIXI"
elif command -v pixi >/dev/null 2>&1; then
  pixi="$(command -v pixi)"
elif [ -x "$HOME/.pixi/bin/pixi" ]; then
  pixi="$HOME/.pixi/bin/pixi"
fi

if [ -z "$pixi" ]; then
  printf 'Error: Pixi was not found. Run setup again or install Pixi first.\n' >&2
  exit 127
fi

cd "$app_dir"
exec "$pixi" run wgsextract "$@"
