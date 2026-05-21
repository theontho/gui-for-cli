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
  printf '"'
  printf '%s' "$1" | LC_ALL=C od -An -v -t u1 | while IFS=' ' read -r bytes; do
    for byte in $bytes; do
      case "$byte" in
        8) printf '\\b' ;;
        9) printf '\\t' ;;
        10) printf '\\n' ;;
        12) printf '\\f' ;;
        13) printf '\\r' ;;
        34) printf '\\"' ;;
        92) printf '\\\\' ;;
        [0-9]|1[0-9]|2[0-9]|3[01]) printf '\\u%04x' "$byte" ;;
        *) printf '%b' "\\0$(printf '%03o' "$byte")" ;;
      esac
    done
  done
  printf '"'
}

gene_map_installed=0
library_bootstrapped=0
test_genome_installed=0
test_genome_status="missing"
test_genome_path="$genome_library/wgsextract-benchmark-hg19-mini"
annotation_vcf_file=""
spliceai_file=""
alphamissense_file=""
pharmgkb_file=""
custom_annotation_vcf="${GUI_FOR_CLI_FIELD_vcf_ann_vcf:-}"
input_vcf="${GUI_FOR_CLI_FIELD_vcf_path:-}"

build_hint() {
  combined="$(printf '%s %s' "$input_vcf" "$ref_path" | tr '[:upper:]' '[:lower:]')"
  case "$combined" in
    *hg38*|*grch38*|*hs38*) printf 'hg38' ;;
    *hg19*|*grch37*|*hs37*) printf 'hg19' ;;
    *) printf '' ;;
  esac
}

first_existing_named_file() {
  dirs="$1"
  names="$2"
  for dir in $dirs; do
    [ -d "$dir" ] || continue
    for name in $names; do
      candidate="$dir/$name"
      if [ -f "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
      fi
    done
  done
  return 1
}

first_existing_pattern_file() {
  dirs="$1"
  patterns="$2"
  for dir in $dirs; do
    [ -d "$dir" ] || continue
    for pattern in $patterns; do
      for candidate in "$dir"/$pattern; do
        if [ -f "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
      done
    done
  done
  return 1
}

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

  annotation_dirs="$ref_path $ref_path/ref $ref_path/microarray $ref_path/genomes/microarray"
  annotation_names="All_SNPs.vcf.gz common_all.vcf.gz snps_hg19.vcf.gz snps_hg38.vcf.gz snps_grch37.vcf.gz snps_grch38.vcf.gz All_SNPs_hg19_ref.tab.gz All_SNPs_hg38_ref.tab.gz All_SNPs_HG19_ref.tab.gz All_SNPs_HG38_ref.tab.gz All_SNPs_GRCh37_ref.tab.gz All_SNPs_GRCh38_ref.tab.gz All_SNPs_grch37_ref.tab.gz All_SNPs_grch38_ref.tab.gz"
  annotation_vcf_file="$(first_existing_named_file "$annotation_dirs" "$annotation_names" || true)"
  ref_dirs="$ref_path $ref_path/ref"
  hint="$(build_hint)"
  spliceai_patterns="spliceai*.vcf.gz spliceai*.vcf.bgz"
  alphamissense_patterns="alphamissense*.tsv.gz alphamissense*.vcf.gz alphamissense*.vcf.bgz"
  pharmgkb_patterns="pharmgkb*.vcf.gz pharmgkb*.vcf.bgz pharmgkb*.tsv.gz"
  if [ -n "$hint" ]; then
    spliceai_patterns="spliceai*$hint*.vcf.gz spliceai*$hint*.vcf.bgz $spliceai_patterns"
    alphamissense_patterns="alphamissense*$hint*.tsv.gz alphamissense*$hint*.vcf.gz alphamissense*$hint*.vcf.bgz $alphamissense_patterns"
    pharmgkb_patterns="pharmgkb*$hint*.vcf.gz pharmgkb*$hint*.vcf.bgz pharmgkb*$hint*.tsv.gz $pharmgkb_patterns"
  fi
  spliceai_file="$(first_existing_pattern_file "$ref_dirs" "$spliceai_patterns" || true)"
  alphamissense_file="$(first_existing_pattern_file "$ref_dirs" "$alphamissense_patterns" || true)"
  pharmgkb_file="$(first_existing_pattern_file "$ref_dirs" "$pharmgkb_patterns" || true)"
fi

if [ -d "$test_genome_path" ] && [ -f "$test_genome_path/genome-config.toml" ]; then
  test_genome_installed=1
  test_genome_status="installed"
elif [ -f "$genome_library/.downloads/wgsextract-benchmark-hg19-mini.zip.partial" ]; then
  test_genome_status="incomplete"
fi

if [ -n "$custom_annotation_vcf" ]; then
  annotation_vcf_argument="$custom_annotation_vcf"
else
  annotation_vcf_argument="$annotation_vcf_file"
fi
if [ -n "$annotation_vcf_argument" ]; then
  annotation_vcf_ready=1
else
  annotation_vcf_ready=0
fi

printf '{"values":{"library.geneMapInstalled":"%s","library.isBootstrapped":"%s","library.annotationVcfInstalled":"%s","library.annotationVcfFile":%s,"library.annotationVcfArgument":%s,"library.annotationVcfReady":"%s","library.spliceaiInstalled":"%s","library.spliceaiFile":%s,"library.alphamissenseInstalled":"%s","library.alphamissenseFile":%s,"library.pharmgkbInstalled":"%s","library.pharmgkbFile":%s,"library.testGenomeInstalled":"%s","library.testGenomeStatus":%s,"library.testGenomePath":%s}}\n' \
  "$(json_bool "$gene_map_installed")" \
  "$(json_bool "$library_bootstrapped")" \
  "$(json_bool "$([ -n "$annotation_vcf_file" ] && printf 1 || printf 0)")" \
  "$(json_string "$annotation_vcf_file")" \
  "$(json_string "$annotation_vcf_argument")" \
  "$(json_bool "$annotation_vcf_ready")" \
  "$(json_bool "$([ -n "$spliceai_file" ] && printf 1 || printf 0)")" \
  "$(json_string "$spliceai_file")" \
  "$(json_bool "$([ -n "$alphamissense_file" ] && printf 1 || printf 0)")" \
  "$(json_string "$alphamissense_file")" \
  "$(json_bool "$([ -n "$pharmgkb_file" ] && printf 1 || printf 0)")" \
  "$(json_string "$pharmgkb_file")" \
  "$(json_bool "$test_genome_installed")" \
  "$(json_string "$test_genome_status")" \
  "$(json_string "$test_genome_path")"
