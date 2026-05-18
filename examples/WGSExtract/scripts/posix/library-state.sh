#!/bin/sh
set -eu

ref_path="${1:-}"
if [ -z "$ref_path" ]; then
  ref_path="${GUI_FOR_CLI_FIELD_ref_path:-}"
fi

json_bool() {
  if [ "$1" = "1" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

gene_map_installed=0
library_bootstrapped=0

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

printf '{"values":{"library.geneMapInstalled":"%s","library.isBootstrapped":"%s"}}\n' \
  "$(json_bool "$gene_map_installed")" \
  "$(json_bool "$library_bootstrapped")"
