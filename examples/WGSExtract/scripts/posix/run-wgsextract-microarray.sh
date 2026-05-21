#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "microarray" ]; then
  shift
fi

arg_value() {
  name="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      "$name")
        shift
        if [ "$#" -gt 0 ]; then
          printf '%s\n' "$1"
          return 0
        fi
        ;;
      "$name="*)
        printf '%s\n' "${1#*=}"
        return 0
        ;;
    esac
    shift
  done
  return 1
}

has_arg() {
  name="$1"
  shift
  for arg in "$@"; do
    case "$arg" in
      "$name"|"$name="*) return 0 ;;
    esac
  done
  return 1
}

input_stem() {
  name="$(basename "$1")"
  case "$name" in
    *.vcf.gz) printf '%s\n' "${name%.vcf.gz}" ;;
    *.bam) printf '%s\n' "${name%.bam}" ;;
    *.cram) printf '%s\n' "${name%.cram}" ;;
    *.vcf) printf '%s\n' "${name%.vcf}" ;;
    *.bcf) printf '%s\n' "${name%.bcf}" ;;
    *.*) printf '%s\n' "${name%.*}" ;;
    *) printf '%s\n' "$name" ;;
  esac
}

first_existing_file() {
  for candidate in "$@"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

single_matching_file() {
  directory="$1"
  shift
  [ -n "$directory" ] && [ -d "$directory" ] || return 1
  found=""
  count=0
  for pattern in "$@"; do
    for candidate in "$directory"/$pattern; do
      [ -f "$candidate" ] || continue
      count=$((count + 1))
      found="$candidate"
    done
  done
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

build_target_names() {
  printf '%s\n' "All_SNPs.vcf.gz" "common_all.vcf.gz"
  for hint in "$@"; do
    lower="$(printf '%s' "$hint" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      *hg38*|*grch38*|*hs38*)
        printf '%s\n' \
          "snps_hg38.vcf.gz" \
          "All_SNPs_hg38_ref.tab.gz" \
          "All_SNPs_HG38_ref.tab.gz" \
          "All_SNPs_GRCh38_ref.tab.gz" \
          "All_SNPs_grch38_ref.tab.gz" \
          "snps_grch38.vcf.gz"
        ;;
    esac
    case "$lower" in
      *hg19*|*hg37*|*grch37*|*hs37*)
        printf '%s\n' \
          "snps_hg19.vcf.gz" \
          "All_SNPs_hg19_ref.tab.gz" \
          "All_SNPs_HG19_ref.tab.gz" \
          "All_SNPs_GRCh37_ref.tab.gz" \
          "All_SNPs_grch37_ref.tab.gz" \
          "snps_grch37.vcf.gz"
        ;;
    esac
  done | awk '!seen[$0]++'
}

reference_target_directories() {
  reference="$1"
  [ -n "$reference" ] || return 0
  root="$reference"
  if [ -f "$root" ]; then
    root="$(dirname "$root")"
  fi
  printf '%s\n' "$root" "$root/ref" "$root/microarray" "$root/genomes/microarray"
}

reference_fasta_candidates() {
  directory="$1"
  [ -n "$directory" ] && [ -d "$directory" ] || return 0
  find "$directory" -maxdepth 1 -type f \( -name '*.fa' -o -name '*.fasta' -o -name '*.fna' -o -name '*.fa.gz' -o -name '*.fasta.gz' -o -name '*.fna.gz' \) -print 2>/dev/null
}

select_reference_fasta() {
  candidates="$1"
  shift
  [ -n "$candidates" ] || return 1
  patterns=""
  for hint in "$@"; do
    lower="$(printf '%s' "$hint" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      *hg19*|*hg37*|*grch37*|*hs37*) patterns="$patterns hg19 hg37 grch37 hs37" ;;
    esac
    case "$lower" in
      *hg38*|*grch38*|*hs38*) patterns="$patterns hg38 grch38 hs38" ;;
    esac
  done
  for pattern in $patterns; do
    resolved="$(
      printf '%s\n' "$candidates" | while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        lower="$(basename "$candidate" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
          *"$pattern"*) printf '%s\n' "$candidate"; break ;;
        esac
      done
    )"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  done
  candidate_count="$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$candidate_count" = "1" ]; then
    printf '%s\n' "$candidates" | sed '/^$/d'
    return 0
  fi
  return 1
}

resolve_input_reference_fasta() {
  input_path="$1"
  [ -n "$input_path" ] || return 1
  directory="$(dirname "$input_path")"
  [ -d "$directory" ] || return 1
  manifest="$directory/manifest.json"
  if [ -f "$manifest" ]; then
    ref_file="$(sed -n 's/.*"ref"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1 || true)"
    if [ -n "$ref_file" ] && [ -f "$directory/$ref_file" ]; then
      printf '%s\n' "$directory/$ref_file"
      return 0
    fi
  fi
  candidates="$(reference_fasta_candidates "$directory")"
  select_reference_fasta "$candidates" "$input_path"
}

resolve_reference_fasta() {
  reference="$1"
  input_path="$2"

  case "$reference" in
    *.fa|*.fasta|*.fna|*.fa.gz|*.fasta.gz|*.fna.gz)
      if [ -f "$reference" ]; then
        printf '%s\n' "$reference"
        return 0
      fi
      ;;
  esac

  candidates=""
  if [ -n "$reference" ] && [ -d "$reference" ]; then
    candidates="$(reference_fasta_candidates "$reference"; reference_fasta_candidates "$reference/genomes")"
  fi
  resolved="$(select_reference_fasta "$candidates" "$input_path" "$reference" || true)"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  resolved="$(resolve_input_reference_fasta "$input_path" || true)"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  printf '%s\n' "$reference"
}

resolve_input_target_tab() {
  input_path="$1"
  [ -n "$input_path" ] || return 1
  directory="$(dirname "$input_path")"
  [ -d "$directory" ] || return 1
  stem="$(input_stem "$input_path")"
  first_existing_file \
    "$directory/$stem.targets.tab.gz" \
    "$directory/$stem.target.tab.gz" \
    "$directory/$stem.snps.tab.gz" && return 0
  single_matching_file "$directory" \
    "*.targets.tab.gz" \
    "*.target.tab.gz" \
    "*.snps.tab.gz" \
    "All_SNPs*.tab.gz" \
    "All_SNPs*.vcf.gz" \
    "snps_*.vcf.gz" \
    "common_all.vcf.gz"
}

resolve_reference_target_tab() {
  reference_a="$1"
  reference_b="$2"
  shift 2
  directories="$(
    for reference in "$reference_a" "$reference_b"; do
      reference_target_directories "$reference"
    done | awk 'NF && !seen[$0]++'
  )"

  resolved="$(
    build_target_names "$@" | while IFS= read -r target_name; do
      [ -n "$target_name" ] || continue
      printf '%s\n' "$directories" | while IFS= read -r directory; do
        [ -n "$directory" ] && [ -d "$directory" ] || continue
        candidate="$directory/$target_name"
        if [ -f "$candidate" ]; then
          printf '%s\n' "$candidate"
          exit 0
        fi
      done
    done | sed -n '1p'
  )"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  resolved="$(
    printf '%s\n' "$directories" | while IFS= read -r directory; do
      [ -n "$directory" ] || continue
      single_matching_file "$directory" \
        "All_SNPs*.tab.gz" \
        "All_SNPs*.vcf.gz" \
        "snps_*.vcf.gz" \
        "common_all.vcf.gz" && break
    done | sed -n '1p'
  )"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  return 1
}

input_path="$(arg_value --input "$@" || true)"
ref_path="$(arg_value --ref "$@" || true)"
original_ref_path="$ref_path"
resolved_ref_path="$(resolve_reference_fasta "$ref_path" "$input_path")"
if [ -n "$resolved_ref_path" ] && [ "$resolved_ref_path" != "$ref_path" ]; then
  original_arg_count=$#
  processed_arg_count=0
  replaced=0
  while [ "$processed_arg_count" -lt "$original_arg_count" ]; do
    argument="$1"
    shift
    processed_arg_count=$((processed_arg_count + 1))
    case "$argument" in
      --ref)
        set -- "$@" "$argument" "$resolved_ref_path"
        if [ "$processed_arg_count" -lt "$original_arg_count" ]; then
          shift
          processed_arg_count=$((processed_arg_count + 1))
        fi
        replaced=1
        ;;
      --ref=*)
        set -- "$@" "--ref=$resolved_ref_path"
        replaced=1
        ;;
      *)
        set -- "$@" "$argument"
        ;;
    esac
  done
  if [ "$replaced" -eq 0 ]; then
    set -- "$@" --ref "$resolved_ref_path"
  fi
  ref_path="$resolved_ref_path"
fi

if ! has_arg --ref-vcf-tab "$@"; then
  target_tab="$(resolve_input_target_tab "$input_path" || resolve_reference_target_tab "$ref_path" "$original_ref_path" "$ref_path" "$original_ref_path" "$input_path" || true)"
  if [ -n "$target_tab" ]; then
    set -- "$@" --ref-vcf-tab "$target_tab"
  fi
fi

exec sh "$script_dir/run-wgsextract-env.sh" wgsextract microarray "$@"
