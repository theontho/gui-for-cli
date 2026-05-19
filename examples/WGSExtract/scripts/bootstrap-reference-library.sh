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
    case "$name" in
      ._*|.DS_Store)
        rm -rf "$entry"
        continue
        ;;
    esac
    target="$dst/$name"
    if [ -d "$entry" ] && [ ! -L "$entry" ]; then
      merge_tree "$entry" "$target"
      rmdir "$entry" 2>/dev/null || true
    elif [ ! -e "$target" ]; then
      mv "$entry" "$target"
    elif cmp -s "$entry" "$target" 2>/dev/null; then
      rm -f "$entry"
    else
      printf 'Warning: leaving duplicate bootstrap file in place: %s\n' "$entry" >&2
    fi
  done
}

normalize_bootstrap_layout() {
  nested="$reference_library/reference"
  if [ -d "$nested" ]; then
    merge_tree "$nested" "$reference_library"
    find "$nested" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true
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
  if ! sh "$script_dir/run-wgsextract-env.sh" bcftools call --ploidy "$alias?" > "$tmp" 2>&1; then
    :
  fi
  if [ -s "$tmp" ] && grep -q '^\*' "$tmp"; then
    mv "$tmp" "$output"
  else
    cat "$tmp" >&2 || true
    rm -f "$tmp"
    return 1
  fi
}

bootstrap_has_content() {
  find "$reference_library" -type f \
    ! -name 'ploidy_*.txt' \
    ! -name '.DS_Store' \
    ! -name '._*' \
    ! -name '.*' \
    -print -quit | grep -q .
}

mkdir -p "$reference_library"
normalize_bootstrap_layout
if ! bootstrap_has_content; then
  sh "$bundle_root/scripts/run-wgsextract.sh" ref bootstrap --ref "$reference_library"
  normalize_bootstrap_layout
fi
install_ploidy_file GRCh37 "$reference_library/ploidy_hg19.txt"
install_ploidy_file GRCh38 "$reference_library/ploidy_hg38.txt"
