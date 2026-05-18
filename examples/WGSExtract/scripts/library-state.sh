#!/bin/sh
set -eu

ref_path="${1:-}"
if [ -z "$ref_path" ]; then
  ref_path="${GUI_FOR_CLI_FIELD_ref_path:-}"
fi
genome_library="${2:-}"
if [ -z "$genome_library" ]; then
  genome_library="${GUI_FOR_CLI_FIELD_genome_library:-${GUI_FOR_CLI_CONFIG_genome_library:-${GUI_FOR_CLI_CONFIG_wgs_settings_genome_library:-}}}"
fi
if [ -z "$genome_library" ]; then
  genome_library="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}/genomes"
fi

json_bool() {
  if [ "$1" = "1" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

json_string() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

gene_map_installed=0
library_bootstrapped=0
test_genome_installed=0
test_genome_status="missing"
test_genome_path="$genome_library/wgsextract-benchmark-hg19-mini"

if [ -n "$ref_path" ]; then
  ref_dir="$ref_path/ref"
  if [ -f "$ref_dir/genes_hg19.tsv" ] && [ -f "$ref_dir/genes_hg38.tsv" ]; then
    gene_map_installed=1
  fi

  if [ -d "$ref_path" ]; then
    if find "$ref_path" -type f \
      ! -name 'genes_hg19.tsv' \
      ! -name 'genes_hg38.tsv' \
      ! -name '.DS_Store' \
      -print -quit | grep -q .; then
      library_bootstrapped=1
    fi
  fi
fi

if [ -d "$test_genome_path" ] && [ -f "$test_genome_path/genome-config.toml" ]; then
  test_genome_installed=1
  test_genome_status="installed"
elif [ -f "$genome_library/.downloads/wgsextract-benchmark-hg19-mini.zip.partial" ]; then
  test_genome_status="incomplete"
fi

printf '{"values":{"library.geneMapInstalled":"%s","library.isBootstrapped":"%s","library.testGenomeInstalled":"%s","library.testGenomeStatus":%s,"library.testGenomePath":%s}}\n' \
  "$(json_bool "$gene_map_installed")" \
  "$(json_bool "$library_bootstrapped")" \
  "$(json_bool "$test_genome_installed")" \
  "$(json_string "$test_genome_status")" \
  "$(json_string "$test_genome_path")"
