#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "microarray" ]; then
  exec sh "$script_dir/run-wgsextract-microarray.sh" "$@"
fi

exec sh "$script_dir/run-wgsextract-env.sh" wgsextract "$@"
