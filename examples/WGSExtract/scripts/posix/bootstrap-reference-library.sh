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
    printf 'Ploidy file already installed: %s\n' "$output"
    return 0
  fi
  printf 'Installing ploidy file for %s: %s\n' "$alias" "$output"
  printf 'Running: bcftools call --ploidy %s? (this may take a moment while Pixi starts the bundled environment)\n' "$alias"
  tmp="$(mktemp "${output}.tmp.XXXXXX")"
  sh "$script_dir/run-wgsextract-env.sh" bcftools call --ploidy "$alias?" > "$tmp" 2>&1 &
  pid="$!"
  started_at="$(date +%s)"
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    if kill -0 "$pid" 2>/dev/null; then
      now="$(date +%s)"
      printf 'Still generating %s ploidy file after %ss (pid %s); waiting for bcftools/Pixi...\n' "$alias" "$((now - started_at))" "$pid"
    fi
  done
  if ! wait "$pid"; then
    :
  fi
  if [ -s "$tmp" ] && grep -q '^\*' "$tmp"; then
    mv "$tmp" "$output"
    printf 'Installed ploidy file: %s\n' "$output"
  else
    cat "$tmp" >&2 || true
    rm -f "$tmp"
    return 1
  fi
}

should_install_mappability_maps() {
  [ "${WGSEXTRACT_SKIP_MAPPABILITY_MAPS:-}" != "1" ]
}

write_mappability_maps_status() {
  if should_install_mappability_maps; then
    printf 'Mappability maps are part of setup; wgsextract ref bootstrap handles them with --install-mappability-maps.\n'
  else
    printf 'Skipping mappability map installation because WGSEXTRACT_SKIP_MAPPABILITY_MAPS=1.\n'
  fi
}

run_reference_bootstrap() {
  if should_install_mappability_maps; then
    printf 'Running reference bootstrap with mappability maps enabled.\n'
    sh "$script_dir/run-wgsextract.sh" ref bootstrap --ref "$reference_library" --install-mappability-maps
  else
    printf 'Running reference bootstrap without mappability maps.\n'
    sh "$script_dir/run-wgsextract.sh" ref bootstrap --ref "$reference_library"
  fi
}

bootstrap_has_support_assets() {
  find "$reference_library" "$reference_library/ref" "$reference_library/microarray" \
    -type f \( -name 'All_SNPs*.tab.gz' -o -name 'All_SNPs*.vcf.gz' -o -name 'snps_*.vcf.gz' -o -name 'common_all.vcf.gz' \) \
    -print -quit 2>/dev/null | grep -q .
}

install_bootstrap_support_files() {
  install_ploidy_file GRCh37 "$reference_library/ploidy_hg19.txt"
  install_ploidy_file GRCh38 "$reference_library/ploidy_hg38.txt"
  write_mappability_maps_status
  printf 'Reference bootstrap support files are ready.\n'
}

mkdir -p "$reference_library"
normalize_bootstrap_layout
if bootstrap_has_support_assets; then
  if should_install_mappability_maps; then
    run_reference_bootstrap
    normalize_bootstrap_layout
  fi
  install_bootstrap_support_files
  exit 0
fi

attempt=1
while [ "$attempt" -le 3 ]; do
  if run_reference_bootstrap; then
    normalize_bootstrap_layout
    install_bootstrap_support_files
    exit 0
  fi
  if [ "$attempt" -lt 3 ]; then
    sleep "$((attempt * 2))"
  fi
  attempt="$((attempt + 1))"
done
exit 1
