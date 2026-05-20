#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"

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

has_ploidy_args() {
  for arg in "$@"; do
    case "$arg" in
      --ploidy|--ploidy=*|--ploidy-file|--ploidy-file=*) return 0 ;;
    esac
  done
  return 1
}

has_map_args() {
  for arg in "$@"; do
    case "$arg" in
      -M|--map|-M=*|--map=*) return 0 ;;
    esac
  done
  return 1
}

detect_ploidy_alias() {
  for value in "$@"; do
    lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      *hg19*|*hg37*|*grch37*|*hs37*) printf 'GRCh37\n'; return 0 ;;
      *hg38*|*grch38*|*hs38*) printf 'GRCh38\n'; return 0 ;;
    esac
  done
  return 1
}

find_mappability_map() {
  library="$1"
  alias="$2"
  [ -n "$library" ] || return 1
  if [ -f "$library" ]; then
    library="$(dirname "$library")"
  fi
  case "$alias" in
    GRCh37) build="hg19" ;;
    GRCh38) build="hg38" ;;
    *) return 1 ;;
  esac
  for dir in "$library/maps" "$library" "$library/ref" "$library/reference/maps" "$library/reference"; do
    [ -d "$dir" ] || continue
    for file in "$dir/$build.map.gz" "$dir/$build.map" "$dir/${alias}.map.gz" "$dir/${alias}.map"; do
      if [ -f "$file" ]; then
        printf '%s\n' "$file"
        return 0
      fi
    done
  done
  return 1
}

find_ploidy_file() {
  library="$1"
  alias="$2"
  [ -n "$library" ] || return 1
  if [ -f "$library" ]; then
    library="$(dirname "$library")"
  fi
  case "$alias" in
    GRCh37) build="hg19" ;;
    GRCh38) build="hg38" ;;
    *) return 1 ;;
  esac
  for dir in "$library" "$library/ref" "$library/microarray" "$library/reference" "$library/reference/ref" "$library/reference/microarray"; do
    [ -d "$dir" ] || continue
    for file in "$dir/ploidy_$build.txt" "$dir/ploidy_$alias.txt" "$dir/ploidy.txt"; do
      if [ -f "$file" ]; then
        printf '%s\n' "$file"
        return 0
      fi
    done
  done
  return 1
}

if [ "$#" -lt 1 ]; then
  printf 'Usage: %s VCF_SUBCOMMAND [ARG...]\n' "$0" >&2
  exit 64
fi

subcommand="$1"
case "$subcommand" in
  snp|indel|cnv) ;;
  *) exec sh "$script_dir/run-wgsextract.sh" vcf "$@" ;;
esac

ref_path="$(arg_value --ref "$@" || true)"
input_path="$(arg_value --input "$@" || true)"
alias="$(
  detect_ploidy_alias \
    "$ref_path" \
    "$input_path" \
    "${GUI_FOR_CLI_FIELD_ref_fasta:-}" \
    "${GUI_FOR_CLI_CONFIG_reference_fasta:-}" \
    "${GUI_FOR_CLI_CONFIG_wgs_settings_ref_fasta:-}" \
    "${GUI_FOR_CLI_CONFIG_wgs_settings_reference_fasta:-}" \
    || true
)"

if [ "$subcommand" = "cnv" ] && ! has_map_args "$@"; then
  map_file="$(find_mappability_map "$ref_path" "$alias" || true)"
  if [ -n "$map_file" ]; then
    exec sh "$script_dir/run-wgsextract.sh" vcf "$@" --map "$map_file"
  fi
fi

if has_ploidy_args "$@"; then
  exec sh "$script_dir/run-wgsextract.sh" vcf "$@"
fi

if [ -n "$alias" ]; then
  ploidy_file="$(find_ploidy_file "$ref_path" "$alias" || true)"
  if [ -n "$ploidy_file" ]; then
    exec sh "$script_dir/run-wgsextract.sh" vcf "$@" --ploidy-file "$ploidy_file"
  fi
  exec sh "$script_dir/run-wgsextract.sh" vcf "$@" --ploidy "$alias"
fi

exec sh "$script_dir/run-wgsextract.sh" vcf "$@"
