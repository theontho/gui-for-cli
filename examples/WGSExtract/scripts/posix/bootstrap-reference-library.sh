#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
reference_library="${WGSEXTRACT_REFERENCE_LIBRARY:-$bundle_root/reference}"

set -- ref bootstrap --ref "$reference_library"
if [ "${WGSEXTRACT_SKIP_MAPPABILITY_MAPS:-}" != "1" ]; then
  set -- "$@" --install-mappability-maps
fi

exec sh "$script_dir/run-wgsextract.sh" "$@"
