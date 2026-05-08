#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
library="${2:-}"
if [[ -z "$library" ]]; then
  library="${GUI_FOR_CLI_CONFIG_REFERENCE_LIBRARY:-}"
fi
if [[ -z "$library" ]]; then
  library="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$PWD}/reference"
fi
genomes_dir="$library/genomes"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

status_for() {
  local final="$1"
  local path="$genomes_dir/$final"
  if [[ -f "$path" && -f "$path.fai" ]]; then
    printf 'installed'
  elif [[ -f "$path" ]]; then
    printf 'unindexed'
  elif [[ -f "$path.partial" ]]; then
    printf 'incomplete'
  else
    printf 'missing'
  fi
}

size_for() {
  local final="$1"
  local path="$genomes_dir/$final"
  local total=0
  local candidate
  for candidate in "$path" "$path.partial" "$path.fai" "$path.gzi" "$path.dict"; do
    if [[ -f "$candidate" ]]; then
      total=$((total + $(wc -c <"$candidate")))
    fi
  done
  if (( total == 0 )); then
    printf ''
  elif (( total > 1073741824 )); then
    awk -v bytes="$total" 'BEGIN { printf "%.1f GB", bytes / 1073741824 }'
  else
    awk -v bytes="$total" 'BEGIN { printf "%.1f MB", bytes / 1048576 }'
  fi
}

build_for() {
  local code="$1"
  local final="$2"
  local description="$3"
  case "$code $final $description" in
    *GRCh37*|*hg19*|*hs37*|*hg37*) printf 'GRCh37 / hg19' ;;
    *GRCh38*|*hg38*|*hs38*) printf 'GRCh38 / hg38' ;;
    *T2T*|*CHM13*|*chm13*|*HG002*) printf 'T2T / CHM13' ;;
    *Dog*|*Canis*|*GSD*) printf 'Dog' ;;
    *Cat*|*Felis*|*Fca*) printf 'Cat' ;;
    *) printf '%s' "$final" ;;
  esac
}

selected_option() {
  local index="$1"
  local status="$2"
  if [[ "$status" == "installed" ]]; then
    printf 'true'
    return
  fi
  if [[ "$index" == "0" ]]; then
    printf 'true'
    return
  fi
  printf 'false'
}

tags_json_for() {
  local label="$1"
  local first=true
  printf '['
  if [[ "$label" == *"(Rec)"* ]]; then
    printf '{"id":"recommended","title":"Recommended","style":"primary"}'
    first=false
  fi
  printf ']'
}

find_seed_catalog() {
  local candidate
  for candidate in \
    "${WGSEXTRACT_REFERENCE_CATALOG:-}" \
    "${GUI_FOR_CLI_BUNDLE_ROOT:-}/runtime/wgsextract-cli/app/src/wgsextract_cli/assets/reference/seed_genomes.csv" \
    "${GUI_FOR_CLI_BUNDLE_ROOT:-}/runtime/wgsextract-cli/app/wgsextract_cli/assets/reference/seed_genomes.csv" \
    "${GUI_FOR_CLI_BUNDLE_ROOT:-}/assets/reference/seed_genomes.csv" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/assets/reference/seed_genomes.csv"
  do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

seed_catalog_records() {
  local catalog="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$catalog" <<'PY'
import csv
import sys

catalog = sys.argv[1]
with open(catalog, newline="", encoding="utf-8-sig") as handle:
    for row in csv.DictReader(handle):
        code = (row.get("Pyth Code") or "").strip()
        source = (row.get("Source") or "").strip()
        final = (row.get("Final File Name") or "").strip()
        label = (row.get("Library Menu Label") or "").strip()
        description = (row.get("Description") or "").strip()
        if not code or not source or not final or not label:
            continue
        values = [code, label, final, source, description]
        print("|".join(value.replace("|", "/") for value in values))
PY
}

genome_records() {
  local catalog
  if catalog="$(find_seed_catalog)" && seed_catalog_records "$catalog"; then
    return
  fi
  cat <<'GENOMES'
T2Tv20|T2T_v2.0 (PGP/HPP chrN) (Rec)|chm13v2.0.fa.gz|AWS|T2T v2.0 (chm13 v1.1; HG002 Y v2.7; UCSC SN; @AWS)
hs38|hs38 (Nebula) (GitHub) (Rec)|hs38.fa.gz|GitHub|hs38 No Alt (1K Genome; @GitHub)
hs38d1|hs38d1 (Nebula New) (GitHub)|hs38d1.fna.gz|GitHub|hs38d1 No Alt + 2385 hs38d1 Decoys (1K; @GitHub)
hs38DH|hs38DH (aDNA) (GitHub) 3x|hs38DH.fa.gz|GitHub|hs38DH (1K Genome; @GitHub)
hs38d1a|hs38d1a (1K Gen+) (GitHub)|hs38d1a.fna.gz|GitHub|hs38d1a Full Anal + 2385 hs38d1 Decoys (1K; @GitHub)
hs37|hs37 (1K Gen) (GitHub)|hs37.fa.gz|GitHub|hs37 (1K Genome; @GitHub)
hs38d1v|hs38d1v (Verily; unique) (GitHub)|GRCh38_Verily_v1.genome.fa.gz|GitHub|hs38d1 by Google Verily (unique; @GitHub)
hs38d1s|hs38d1s (by Sequencing) (GitHub)|hs38d1s.fa.gz|GitHub|hs38d1s (Sequencing.com; hs38d1+22_KI270879v1_alt) (@GitHub)
hg37w|hg37 (rCRS; WGSE v1) (GitHub)|hg19_WGSE.fa.gz|GitHub|hg19 rCRS (@GitHub)
hs37d5|hs37d5 (Dante) (NIH) (Rec)|hs37d5.fa.gz|NIH-Alt|hs37d5 (1K Genome; @US NIH)
hs38|hs38 (Nebula) (NIH) (Rec)|hs38.fa.gz|NIH-Alt|hs38 No Alt (1K Genome; @US NIH)
hs38d1|hs38d1 (Nebula new) (NIH)|hs38d1.fna.gz|NIH-Alt|hs38d1 No Alt + 2385 hs38d1 Decoys (1K; @US NIH)
hs38DH|hs38DH (aDNA) (NIH) 3x|hs38DH.fa.gz|NIH-Alt|hs38DH (1KGenome; @US NIH; uncompressed so 3x download)
hs38d1a|hs38d1a (1K Gen+) (NIH)|hs38d1a.fna.gz|NIH-Alt|hs38d1a Full Anal + 2385 hs38d1 Decoys (1K; @US NIH)
hs37-|human_g1k_v37 (NIH)|human_g1k_v37.fasta.gz|NIH-Alt|human_g1k_v37 (@US NIH)
hs37d5|hs37d5 (Dante) (EBI) (Rec)|hs37d5.fa.gz|EBI-Alt|hs37d5 (1K Genome; @EU EBI)
hs37-|human_g1k_v37 (EBI)|human_g1k_v37.fasta.gz|EBI-Alt|human_g1k_v37 (@EU EBI)
hg38|hg38 (YSEQ)|hg38.fa.gz|UCSC|hg38 (@UCSC; used by YSEQ)
hg37|hg37 (rCRS; YSEQ)|hg19_yseq.fa.gz|YSEQ|hg19 rCRS (@YSEQ used by YSEQ)
THGySeqp|hg38+hg002y_v2 (by YSEQ) 3x|hg38_CP086569.fasta.gz|YSEQ|T2T yseq (hg38 with HG002 Y v2; @YSEQ; uncompressed 3x download)
hg19|hg19 (yoruba; early Dante)|hg19.fa.gz|UCSC|hg19 Yoruba (@UCSC; used by Dante in 2018)
hs38a|hs38a (1K Gen)|hs38a.fna.gz|NIH|hs38a Full Anal (1K Genome; @US NIH)
THG1243v3|hg01243v3 (PuertoRican1)|hg01243_v3.fna.gz|JHU|T2T HG01243 v3 (aka PR1 Puerto Rican; @JHU)
THGv27|hg002xy_v2.7 (T2T) 3x|hg002xy_v2.7.fasta.gz|AWS|HG002 v2.7 (HG002 XY v2.7; chm13 v1.1; UCSC SN; @AWS)
THGv20|hg002xy_v2 (T2T) 3x|hg002xy_v2.fasta.gz|AWS|HG002 v2 (HG002 XY v2; chm13 v1.1; UCSC SN; @AWS)
HPPv11|chm13y_v1.1 (HPP)|CHM13v11Y.fa.gz|AWS|HPP (chm13 v1.1; GRCh38 Y; @AWS)
HPPv1|chm13y_v1 (HPP)|CHM13v1Y.fa.gz|AWS|HPP (chm13 v1; GRCh38 Y; @AWS)
T2Tv11|T2T_v1.1 Draft|chm13.draft_v1.1.fasta.gz|AWS|T2T v1.1 (chm13 v1.1; no Y; @AWS)
T2Tv10|T2T_v1.0 Draft|chm13.draft_v1.0.fasta.gz|AWS|T2T v1.0 (chm13 v1.0; no Y; @AWS)
T2Tv09|T2T_v0.9 Draft|chm13.draft_v0.9.fasta.gz|AWS|T2T v0.9 (chm13 v0.9; no Y; @AWS)
T2Tv20a|T2T_v2 (PGP/HPP Genbank)|GCA_009914755.4.fna.gz|NIH|T2T v2.0 (Genbank accession SN; @US NIH)
GRCh38|GRCh38 (Ensembl) (patched)|Homo_sapiens.GRCh38.dna.toplevel.fa.gz|EBI|Homo_sapiens.GRCh38 (@EU EBI Ensembl) (latest) (patch 13)
GRCh37|GRCh37 (Ensembl) (patched)|Homo_sapiens.GRCh37.dna.toplevel.fa.gz|EBI|Homo_sapiens.GRCh37 (@EU EBI Ensembl) (latest) (patch 13)
GRCh38-|GRCh38- (Gencode) (primary)|GRCh38.primary_assembly.genome.fa.gz|EBI|GRCh38- (EBI Gencode Base Build 38 Model; @EU EBI) (primary)
GRCh37-|GRCh37- (Gencode) (primary)|GRCh37.primary_assembly.genome.fa.gz|EBI|GRCh37- (EBI Gencode Base Build 37 Model; @EU EBI) (primary)
Dog_UU_GSD|Dog (Canis lupus familiaris) UU_Cfam_GSD_1.0 (NCBI)|GCF_011100685.1_UU_Cfam_GSD_1.0_genomic.fna.gz|NCBI|Dog Genome (GSD 1.0; @US NIH)
Cat_Fca126|Cat (Felis catus) Fca126_mat1.0 (NCBI)|GCF_018350175.1_F.catus_Fca126_mat1.0_genomic.fna.gz|NCBI|Cat Genome (Fca126; @US NIH)
GENOMES
}

printf '{'
if [[ "$mode" == "all" || "$mode" == "options" ]]; then
  printf '"options":['
  first=true
  selected=false
  seen_finals="|"
  index=0
  while IFS='|' read -r code label final source description; do
    if [[ "$seen_finals" == *"|$final|"* ]]; then
      index=$((index + 1))
      continue
    fi
    seen_finals="$seen_finals$final|"
    status="$(status_for "$final")"
    case "$status" in
      installed|unindexed) ;;
      *)
        index=$((index + 1))
        continue
        ;;
    esac
    option_selected=false
    if [[ "$selected" != "true" ]]; then
      option_selected=true
      selected=true
    fi
    $first || printf ','
    first=false
    printf '{"id":"%s","title":"%s (%s)"' \
      "$(json_escape "$genomes_dir/$final")" \
      "$(json_escape "$label")" \
      "$(json_escape "$status")"
    if [[ "$option_selected" == "true" ]]; then
      printf ',"selected":true'
    fi
    printf '}'
    index=$((index + 1))
  done <<EOF
$(genome_records)
EOF
  printf ']'
fi
if [[ "$mode" == "all" ]]; then
  printf ','
fi
if [[ "$mode" == "all" || "$mode" == "items" ]]; then
  printf '"items":['
  first=true
  index=1
  while IFS='|' read -r code label final source description; do
    status="$(status_for "$final")"
    size="$(size_for "$final")"
    build="$(build_for "$code" "$final" "$description")"
    tags="$(tags_json_for "$label")"
    row_id="$code-$source-$final"
    $first || printf ','
    first=false
    printf '{"id":"%s","title":"%s","status":"%s","tags":%s,"tooltip":"%s","values":{"name":"%s","build":"%s","source":"%s","code":"%s","final":"%s","ref":"%s","size":"%s","description":"%s"}}' \
      "$(json_escape "$row_id")" \
      "$(json_escape "$label")" \
      "$(json_escape "$status")" \
      "$tags" \
      "$(json_escape "$description")" \
      "$(json_escape "$label")" \
      "$(json_escape "$build")" \
      "$(json_escape "$source")" \
      "$(json_escape "$code")" \
      "$(json_escape "$final")" \
      "$(json_escape "$genomes_dir/$final")" \
      "$(json_escape "$size")" \
      "$(json_escape "$description")"
    index=$((index + 1))
  done <<EOF
$(genome_records)
EOF
  printf ']'
fi
printf '}\n'
