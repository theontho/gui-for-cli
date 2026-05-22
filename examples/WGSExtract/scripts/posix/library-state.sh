#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
ref_path="${1:-${GUI_FOR_CLI_FIELD_ref_path:-}}"
genome_library="${2:-${GUI_FOR_CLI_FIELD_genome_library:-${GUI_FOR_CLI_CONFIG_genome_library:-${GUI_FOR_CLI_CONFIG_wgs_settings_genome_library:-}}}}"

set -- ref status --values
if [ -n "$ref_path" ]; then
  set -- "$@" --ref "$ref_path"
fi
if [ -n "$genome_library" ]; then
  set -- "$@" --genome-library "$genome_library"
fi
if [ -n "${GUI_FOR_CLI_FIELD_vcf_ann_vcf:-}" ]; then
  set -- "$@" --annotation-vcf "$GUI_FOR_CLI_FIELD_vcf_ann_vcf"
fi
if [ -n "${GUI_FOR_CLI_FIELD_vcf_path:-}" ]; then
  set -- "$@" --input "$GUI_FOR_CLI_FIELD_vcf_path"
fi

exec sh "$script_dir/run-wgsextract.sh" "$@"
