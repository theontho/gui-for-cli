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
  local id="$1"
  if [[ -d "$library/$id" ]] || compgen -G "$library/$id"* >/dev/null 2>&1; then
    printf 'installed'
  else
    printf 'available'
  fi
}

fasta_for() {
  local id="$1"
  local match=""
  if [[ -d "$library/$id" ]]; then
    match="$(find "$library/$id" -maxdepth 2 -type f \( -name '*.fa' -o -name '*.fasta' -o -name '*.fa.gz' -o -name '*.fasta.gz' \) -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "$match" ]]; then
    match="$(find "$library" -maxdepth 2 -type f \( -name "$id*.fa" -o -name "$id*.fasta" -o -name "$id*.fa.gz" -o -name "$id*.fasta.gz" \) -print -quit 2>/dev/null || true)"
  fi
  if [[ -n "$match" ]]; then
    printf '%s' "$match"
  else
    printf '%s/%s/%s.fa' "$library" "$id" "$id"
  fi
}

genome_ids=(hs38DH GRCh38 GRCh37 T2T-CHM13)
genome_names=("hs38DH" "GRCh38" "GRCh37 / hg19" "T2T-CHM13")
genome_builds=("GRCh38" "GRCh38" "GRCh37" "T2T-CHM13")
genome_sources=("WGS Extract reference library" "WGS Extract reference library" "WGS Extract reference library" "WGS Extract reference library")

printf '{'
if [[ "$mode" == "all" || "$mode" == "options" ]]; then
  printf '"options":['
  for index in "${!genome_ids[@]}"; do
    id="${genome_ids[$index]}"
    title="${genome_names[$index]} ($(status_for "$id"))"
    value="$(fasta_for "$id")"
    [[ "$index" == "0" ]] || printf ','
    if [[ "$index" == "0" ]]; then
      printf '{"id":"%s","title":"%s","selected":true}' "$(json_escape "$value")" "$(json_escape "$title")"
    else
      printf '{"id":"%s","title":"%s"}' "$(json_escape "$value")" "$(json_escape "$title")"
    fi
  done
  printf ']'
fi
if [[ "$mode" == "all" ]]; then
  printf ','
fi
if [[ "$mode" == "all" || "$mode" == "items" ]]; then
  printf '"items":['
  for index in "${!genome_ids[@]}"; do
    id="${genome_ids[$index]}"
    [[ "$index" == "0" ]] || printf ','
    printf '{"id":"%s","title":"%s","status":"%s","values":{"name":"%s","build":"%s","source":"%s"}}' \
      "$(json_escape "$id")" \
      "$(json_escape "${genome_names[$index]}")" \
      "$(json_escape "$(status_for "$id")")" \
      "$(json_escape "${genome_names[$index]}")" \
      "$(json_escape "${genome_builds[$index]}")" \
      "$(json_escape "${genome_sources[$index]}")"
  done
  printf ']'
fi
printf '}\n'
