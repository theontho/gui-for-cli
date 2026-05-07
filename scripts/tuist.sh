#!/bin/sh
set -eu

version="4.191.5"
local_tuist="$HOME/.tuist/Versions/$version/tuist"

if [ -x "$local_tuist" ]; then
  exec "$local_tuist" "$@"
fi

exec tuist "$@"
