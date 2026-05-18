#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
reference_library="${WGSEXTRACT_REFERENCE_LIBRARY:-$bundle_root/reference}"

mkdir -p "$reference_library"
attempt=1
while [ "$attempt" -le 3 ]; do
  if "$script_dir/run-wgsextract.sh" ref bootstrap --ref "$reference_library"; then
    exit 0
  fi
  if [ "$attempt" -lt 3 ]; then
    sleep "$((attempt * 2))"
  fi
  attempt="$((attempt + 1))"
done
exit 1
