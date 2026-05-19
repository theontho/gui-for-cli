#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
reference_library="${WGSEXTRACT_REFERENCE_LIBRARY:-$bundle_root/reference}"

merge_tree() {
  src="$1"
  dst="$2"
  mkdir -p "$dst"
  for entry in "$src"/* "$src"/.[!.]* "$src"/..?*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    target="$dst/$name"
    if [ -d "$entry" ] && [ ! -L "$entry" ]; then
      merge_tree "$entry" "$target"
      rmdir "$entry" 2>/dev/null || true
    elif [ ! -e "$target" ]; then
      mv "$entry" "$target"
    else
      printf 'Warning: leaving duplicate bootstrap file in place: %s\n' "$entry" >&2
    fi
  done
}

normalize_bootstrap_layout() {
  nested="$reference_library/reference"
  if [ -d "$nested" ]; then
    merge_tree "$nested" "$reference_library"
    rmdir "$nested" 2>/dev/null || true
  fi
}

install_ploidy_file() {
  alias="$1"
  output="$2"
  if [ -f "$output" ]; then
    return 0
  fi
  tmp="$output.tmp"
  sh "$script_dir/run-wgsextract-env.sh" bcftools call --ploidy "$alias?" > "$tmp"
  mv "$tmp" "$output"
}

mkdir -p "$reference_library"
sh "$bundle_root/scripts/run-wgsextract.sh" ref bootstrap --ref "$reference_library"
normalize_bootstrap_layout
install_ploidy_file GRCh37 "$reference_library/ploidy_hg19.txt"
install_ploidy_file GRCh38 "$reference_library/ploidy_hg38.txt"
