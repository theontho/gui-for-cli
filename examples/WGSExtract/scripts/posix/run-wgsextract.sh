#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"

index_input_message() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *.crai)
      printf 'Selected CRAM index file: %s\nChoose the CRAM data file instead: %s\n' "$1" "${1%?????}" >&2
      return 0
      ;;
    *.bam.bai)
      printf 'Selected BAM index file: %s\nChoose the BAM data file instead: %s\n' "$1" "${1%????}" >&2
      return 0
      ;;
    *.bai)
      printf 'Selected BAM index file: %s\nChoose the BAM data file, not its .bai index.\n' "$1" >&2
      return 0
      ;;
  esac
  return 1
}

previous=""
for argument in "$@"; do
  input_path=""
  if [ "$previous" = "--input" ]; then
    input_path="$argument"
  else
    case "$argument" in
      --input=*) input_path="${argument#--input=}" ;;
    esac
  fi
  if [ -n "$input_path" ] && index_input_message "$input_path"; then
    exit 1
  fi
  previous="$argument"
done

exec sh "$script_dir/run-wgsextract-env.sh" wgsextract "$@"
