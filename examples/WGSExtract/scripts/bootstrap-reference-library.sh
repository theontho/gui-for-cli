#!/bin/sh
set -eu

bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
reference_library="${WGSEXTRACT_REFERENCE_LIBRARY:-$bundle_root/reference}"

mkdir -p "$reference_library"
exec "$bundle_root/scripts/run-wgsextract.sh" ref bootstrap --ref "$reference_library"
