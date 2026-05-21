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
  tmp="$(mktemp "${output}.tmp.XXXXXX")"
  if ! sh "$script_dir/run-wgsextract-env.sh" bcftools call --ploidy "$alias?" > "$tmp" 2>&1; then
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

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_sha256() {
  file="$1"
  expected="$2"
  actual="$(sha256_file "$file")"
  [ "$actual" = "$expected" ]
}

download_if_missing() {
  url="$1"
  output="$2"
  expected_sha256="$3"
  if [ -f "$output" ]; then
    if ! verify_sha256 "$output" "$expected_sha256"; then
      printf 'Warning: checksum mismatch for %s; re-downloading.\n' "$output" >&2
      rm -f "$output"
    else
      return 0
    fi
  fi
  if [ -f "$output" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$output")"
  tmp="$(mktemp "${output}.tmp.XXXXXX")"
  if curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    if ! verify_sha256 "$tmp" "$expected_sha256"; then
      printf 'Error: checksum mismatch for downloaded file: %s\n' "$url" >&2
      rm -f "$tmp"
      return 1
    fi
    mv "$tmp" "$output"
  else
    rm -f "$tmp"
    return 1
  fi
}

install_mappability_maps() {
  maps_dir="$reference_library/maps"
  mkdir -p "$maps_dir"
  required_files="hg19.map.gz hg19.map.gz.fai hg19.map.gz.gzi hg38.map.gz hg38.map.gz.fai hg38.map.gz.gzi"
  missing=0
  for file in $required_files; do
    [ -f "$maps_dir/$file" ] || missing=1
  done
  [ "$missing" -eq 1 ] || return 0

  archive="$(mktemp "$reference_library/wgsextract-delly-mappability-maps.zip.XXXXXX")"
  extract_dir="$(mktemp -d "$reference_library/mappability-maps.XXXXXX")"
  if download_if_missing \
    "https://github.com/theontho/wgsextract-cli/releases/download/v0.1.0/wgsextract-delly-mappability-maps.zip" \
    "$archive" \
    "cab55d8fe28f3c0da90cfdd0a8a4951dc5a33d182bbce3ef34392762eafe5d1b"; then
    if command -v unzip >/dev/null 2>&1; then
      unzip -q "$archive" -d "$extract_dir"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -m zipfile -e "$archive" "$extract_dir"
    elif command -v python >/dev/null 2>&1; then
      python -m zipfile -e "$archive" "$extract_dir"
    else
      printf 'Error: unzip or python is required to extract mappability map archive.\n' >&2
      rm -f "$archive"
      rm -rf "$extract_dir"
      return 1
    fi
    for file in $required_files; do
      if [ ! -f "$extract_dir/maps/$file" ]; then
        printf 'Error: mappability map archive is missing maps/%s\n' "$file" >&2
        rm -f "$archive"
        rm -rf "$extract_dir"
        return 1
      fi
      cp "$extract_dir/maps/$file" "$maps_dir/$file"
    done
  else
    rm -f "$archive"
    rm -rf "$extract_dir"
    return 1
  fi
  rm -f "$archive"
  rm -rf "$extract_dir"
}

install_mappability_maps_optional() {
  if [ "${WGSEXTRACT_SKIP_MAPPABILITY_MAPS:-}" = "1" ]; then
    printf 'Skipping optional mappability maps.\n'
    return 0
  fi
  if [ "${WGSEXTRACT_INSTALL_MAPPABILITY_MAPS:-}" != "1" ]; then
    printf 'Skipping optional mappability map downloads during setup. Set WGSEXTRACT_INSTALL_MAPPABILITY_MAPS=1 to preinstall them.\n'
    return 0
  fi
  printf 'Downloading optional mappability maps...\n'
  if ! install_mappability_maps; then
    printf 'Warning: failed to install mappability maps; continuing without auto-map support.\n' >&2
  else
    printf 'Optional mappability maps are installed.\n'
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
  install_mappability_maps_optional
  printf 'Reference bootstrap support files are ready.\n'
}

mkdir -p "$reference_library"
normalize_bootstrap_layout
if bootstrap_has_support_assets; then
  install_bootstrap_support_files
  exit 0
fi

attempt=1
while [ "$attempt" -le 3 ]; do
  if sh "$script_dir/run-wgsextract.sh" ref bootstrap --ref "$reference_library"; then
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
