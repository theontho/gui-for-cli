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

cnv_map_tmp_dir=""

cleanup_cnv_map() {
  if [ -n "$cnv_map_tmp_dir" ]; then
    rm -rf "$cnv_map_tmp_dir"
    cnv_map_tmp_dir=""
  fi
}

trap cleanup_cnv_map EXIT INT HUP TERM

prepare_cnv_map() {
  map_path="$1"
  case "$map_path" in
    *.gz) ;;
    *) return 0 ;;
  esac
  command -v python3 >/dev/null 2>&1 || {
    printf 'python3 is required to prepare compressed Delly CNV maps.\n' >&2
    return 2
  }
  cnv_map_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wgsextract-cnv-map.XXXXXX")"
  temp_map="$cnv_map_tmp_dir/$(basename "${map_path%.gz}")"
  python3 - "$map_path" "$temp_map" <<'PY' || return $?
import gzip
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

with gzip.open(source, "rt") as src, target.open("w", encoding="utf-8") as dst:
    for line in src:
        dst.write(line)

records = []
current_name = None
current_length = 0
sequence_offset = 0
line_bases = 0
line_width = 0
byte_offset = 0

def finish_record():
    if current_name is not None:
        records.append((current_name, current_length, sequence_offset, line_bases, line_width))

with target.open("rb") as handle:
    while True:
        line = handle.readline()
        if not line:
            break
        if line.startswith(b">"):
            finish_record()
            current_name = line[1:].strip().decode("utf-8").split()[0]
            current_length = 0
            sequence_offset = byte_offset + len(line)
            line_bases = 0
            line_width = 0
        else:
            sequence = line.rstrip(b"\r\n")
            if sequence:
                if line_bases == 0:
                    line_bases = len(sequence)
                    line_width = len(line)
                current_length += len(sequence)
        byte_offset += len(line)
finish_record()

with (target.with_suffix(target.suffix + ".fai")).open("w", encoding="utf-8") as index:
    for name, length, offset, bases, width in records:
        index.write(f"{name}\t{length}\t{offset}\t{bases}\t{width}\n")
PY
  printf '%s\n' "$temp_map"
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
    for file in "$dir/$build-numeric.map.gz" "$dir/$build-numeric.map" "$dir/$build.map.gz" "$dir/$build.map" "$dir/${alias}.map.gz" "$dir/${alias}.map"; do
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
    GRCh37) patterns="hg19 hg37 grch37 hs37" ;;
    GRCh38) patterns="hg38 grch38 hs38" ;;
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
original_ref_path="$ref_path"
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

if [ "$subcommand" = "cnv" ] && ! has_map_args "$@"; then
  map_file="$(find_mappability_map "$ref_path" "$alias" || true)"
  if [ -z "$map_file" ] && [ "$ref_path" != "$original_ref_path" ]; then
    map_file="$(find_mappability_map "$original_ref_path" "$alias" || true)"
  fi
  if [ -n "$map_file" ]; then
    set -- "$@" --map "$map_file"
  fi
fi

if [ "$subcommand" = "cnv" ]; then
  map_path="$(arg_value --map "$@" || arg_value -M "$@" || true)"
  if [ -n "$map_path" ]; then
    set +e
    prepared_map="$(prepare_cnv_map "$map_path")"
    prepare_status=$?
    set -e
    if [ "$prepare_status" -ne 0 ]; then
      printf 'Failed to prepare CNV map %s.\n' "$map_path" >&2
      exit "$prepare_status"
    fi
    if [ -n "$prepared_map" ]; then
      original_arg_count=$#
      processed_arg_count=0
      while [ "$processed_arg_count" -lt "$original_arg_count" ]; do
        argument="$1"
        shift
        processed_arg_count=$((processed_arg_count + 1))
        case "$argument" in
          --map|-M)
            if [ "$processed_arg_count" -lt "$original_arg_count" ]; then
              shift
              processed_arg_count=$((processed_arg_count + 1))
            fi
            ;;
          --map=*|-M=*) ;;
          *) set -- "$@" "$argument" ;;
        esac
      done
      set -- "$@" --map "$prepared_map"
    fi
  fi
  set +e
  sh "$script_dir/run-wgsextract.sh" vcf "$@"
  status=$?
  set -e
  cleanup_cnv_map
  exit "$status"
fi

if has_ploidy_args "$@"; then
  exec sh "$script_dir/run-wgsextract.sh" vcf "$@"
fi

if [ -n "$alias" ]; then
  ploidy_file="$(find_ploidy_file "$ref_path" "$alias" || true)"
  if [ -z "$ploidy_file" ] && [ "$ref_path" != "$original_ref_path" ]; then
    ploidy_file="$(find_ploidy_file "$original_ref_path" "$alias" || true)"
  fi
  if [ -n "$ploidy_file" ]; then
    exec sh "$script_dir/run-wgsextract.sh" vcf "$@" --ploidy-file "$ploidy_file"
  fi
  exec sh "$script_dir/run-wgsextract.sh" vcf "$@" --ploidy "$alias"
fi

exec sh "$script_dir/run-wgsextract.sh" vcf "$@"
