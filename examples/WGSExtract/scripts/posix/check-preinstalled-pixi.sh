#!/bin/sh
set -eu

command_exists() { command -v "$1" >/dev/null 2>&1; }

if [ -n "${PIXI:-}" ]; then
  if [ -x "$PIXI" ]; then
    printf 'Pixi is pre-installed: %s\n' "$PIXI"
  else
    printf 'PIXI is set but is not executable; setup will install Pixi if needed: %s\n' "$PIXI"
  fi
  exit 0
fi

if command_exists pixi; then
  printf 'Pixi is pre-installed: %s\n' "$(command -v pixi)"
elif [ -x "$HOME/.pixi/bin/pixi" ]; then
  printf 'Pixi is pre-installed: %s\n' "$HOME/.pixi/bin/pixi"
else
  printf 'Pixi is not pre-installed; setup will install it if needed.\n'
fi
