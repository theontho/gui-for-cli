#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'Usage: %s INPUT_VCF [OUTPUT_DIR]\n' "$0" >&2
  exit 64
fi

input_path="$1"
out_dir="${2:-}"
script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
runtime="$script_dir/run-wgsextract-env.sh"

if [ -z "$out_dir" ]; then
  out_dir="$(dirname "$input_path")"
fi

mkdir -p "$out_dir"

base_name="$(basename "$input_path")"
case "$base_name" in
  *.vcf.gz) base_name="${base_name%.vcf.gz}" ;;
  *.vcf) base_name="${base_name%.vcf}" ;;
  *) base_name="${base_name%.*}" ;;
esac

tmp_vcf="$(mktemp "$out_dir/${base_name}.XXXXXX.vcf")"
trap 'rm -f "$tmp_vcf"' EXIT INT HUP TERM
sh "$runtime" bcftools view "$input_path" > "$tmp_vcf"
sh "$script_dir/run-wgsextract.sh" repair ftdna-vcf < "$tmp_vcf" \
  > "$out_dir/${base_name}_repaired.vcf"
rm -f "$tmp_vcf"
trap - EXIT INT HUP TERM
