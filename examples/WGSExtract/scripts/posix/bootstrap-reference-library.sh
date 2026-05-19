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
  tmp="$(mktemp "${output}.tmp.XXXXXX")"
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

download_if_missing() {
  url="$1"
  output="$2"
  if [ -f "$output" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$output")"
  tmp="$(mktemp "${output}.tmp.XXXXXX")"
  if curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    mv "$tmp" "$output"
  else
    rm -f "$tmp"
    return 1
  fi
}

install_mappability_maps() {
  maps_dir="$reference_library/maps"
  mkdir -p "$maps_dir"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz" \
    "$maps_dir/hg19.map.gz"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz.fai" \
    "$maps_dir/hg19.map.gz.fai"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh37.dna.primary_assembly.fa.r101.s501.blacklist.gz.gzi" \
    "$maps_dir/hg19.map.gz.gzi"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz" \
    "$maps_dir/hg38.map.gz"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz.fai" \
    "$maps_dir/hg38.map.gz.fai"
  download_if_missing \
    "https://gear-genomics.embl.de/data/delly/Homo_sapiens.GRCh38.dna.primary_assembly.fa.r101.s501.blacklist.gz.gzi" \
    "$maps_dir/hg38.map.gz.gzi"
}

install_mappability_maps_optional() {
  if ! install_mappability_maps; then
    printf 'Warning: failed to install mappability maps; continuing without auto-map support.\n' >&2
  fi
}

bootstrap_has_support_assets() {
  find "$reference_library" "$reference_library/ref" "$reference_library/microarray" \
    -type f \( -name 'All_SNPs*.tab.gz' -o -name 'All_SNPs*.vcf.gz' -o -name 'snps_*.vcf.gz' -o -name 'common_all.vcf.gz' \) \
    -print -quit 2>/dev/null | grep -q .
}

mkdir -p "$reference_library"
normalize_bootstrap_layout
if bootstrap_has_support_assets; then
  install_ploidy_file GRCh37 "$reference_library/ploidy_hg19.txt"
  install_ploidy_file GRCh38 "$reference_library/ploidy_hg38.txt"
  install_mappability_maps_optional
  exit 0
fi

attempt=1
while [ "$attempt" -le 3 ]; do
  if sh "$script_dir/run-wgsextract.sh" ref bootstrap --ref "$reference_library"; then
    normalize_bootstrap_layout
    install_ploidy_file GRCh37 "$reference_library/ploidy_hg19.txt"
    install_ploidy_file GRCh38 "$reference_library/ploidy_hg38.txt"
    install_mappability_maps_optional
    exit 0
  fi
  if [ "$attempt" -lt 3 ]; then
    sleep "$((attempt * 2))"
  fi
  attempt="$((attempt + 1))"
done
exit 1
