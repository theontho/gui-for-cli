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
  parent="$(dirname "$library")"
  case "$alias" in
    GRCh37) build="hg19" ;;
    GRCh38) build="hg38" ;;
    *) return 1 ;;
  esac
  for dir in \
    "$library/maps" "$library" "$library/ref" "$library/reference/maps" "$library/reference" \
    "$parent/maps" "$parent"; do
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
  parent="$(dirname "$library")"
  case "$alias" in
    GRCh37) build="hg19" ;;
    GRCh38) build="hg38" ;;
    *) return 1 ;;
  esac
  for dir in \
    "$library" "$library/ref" "$library/microarray" "$library/reference" "$library/reference/ref" "$library/reference/microarray" \
    "$parent" "$parent/ref" "$parent/microarray"; do
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

reference_fasta_candidates() {
  directory="$1"
  [ -n "$directory" ] && [ -d "$directory" ] || return 0
  find "$directory" -maxdepth 1 -type f \( -name '*.fa' -o -name '*.fasta' -o -name '*.fa.gz' -o -name '*.fasta.gz' \) -print 2>/dev/null
}

select_reference_fasta() {
  alias="$1"
  candidates="$2"
  [ -n "$candidates" ] || return 1
  case "$alias" in
    GRCh37) patterns="hg19 hg37 grch37 hs37 37" ;;
    GRCh38) patterns="hg38 grch38 hs38 38" ;;
    *) patterns="" ;;
  esac
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

resolve_reference_fasta() {
  reference="$1"
  input_path="$2"
  alias="$3"

  case "$reference" in
    *.fa|*.fasta|*.fa.gz|*.fasta.gz)
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
  if [ -n "$candidates" ]; then
    resolved="$(select_reference_fasta "$alias" "$candidates" || true)"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  if [ -n "$input_path" ]; then
    input_dir="$(dirname "$input_path")"
    candidates="$(reference_fasta_candidates "$input_dir")"
    if [ -n "$candidates" ]; then
      resolved="$(select_reference_fasta "$alias" "$candidates" || true)"
      if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
  fi

  printf '%s\n' "$reference"
}

set_arg_value() {
  name="$1"
  value="$2"
  shift 2
  replaced=0
  new_args=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      "$name")
        new_args="${new_args}${new_args:+
}$1
$value"
        shift
        [ "$#" -gt 0 ] && shift
        replaced=1
        ;;
      "$name="*)
        new_args="${new_args}${new_args:+
}$name=$value"
        shift
        replaced=1
        ;;
      *)
        new_args="${new_args}${new_args:+
}$1"
        shift
        ;;
    esac
  done
  if [ "$replaced" -eq 0 ]; then
    new_args="${new_args}${new_args:+
}$name
$value"
  fi
  printf '%s\n' "$new_args"
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

resolved_ref_path="$(resolve_reference_fasta "$ref_path" "$input_path" "$alias")"
if [ -n "$resolved_ref_path" ] && [ "$resolved_ref_path" != "$ref_path" ]; then
  old_ifs="$IFS"
  IFS='
'
  # shellcheck disable=SC2046
  set -- $(set_arg_value --ref "$resolved_ref_path" "$@")
  IFS="$old_ifs"
  ref_path="$resolved_ref_path"
fi

if [ "$subcommand" = "cnv" ] && ! has_map_args "$@"; then
  map_file="$(find_mappability_map "$ref_path" "$alias" || true)"
  if [ -n "$map_file" ]; then
    set -- "$@" --map "$map_file"
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
