#!/usr/bin/env bash
set -euo pipefail

library="${1:-}"
final="${2:-}"
if [[ -z "$library" ]]; then
  library="${GUI_FOR_CLI_CONFIG_REFERENCE_LIBRARY:-}"
fi
if [[ -z "$library" ]]; then
  library="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$PWD}/reference"
fi
if [[ -z "$final" || "$final" == */* || "$final" == *..* ]]; then
  printf 'Invalid reference genome file name: %s\n' "$final" >&2
  exit 2
fi

target_dir="$library/genomes"
target="$target_dir/$final"
if [[ ! -d "$target_dir" ]]; then
  printf 'Reference genome directory does not exist: %s\n' "$target_dir" >&2
  exit 2
fi
case "$(cd "$target_dir" 2>/dev/null && pwd -P)/" in
  "$(cd "$library" 2>/dev/null && pwd -P)/genomes/"*) ;;
  *)
    printf 'Refusing to delete outside the reference library: %s\n' "$target_dir" >&2
    exit 2
    ;;
esac

deleted=false
for suffix in "" ".partial" ".fai" ".gzi" ".dict" ".amb" ".ann" ".bwt" ".pac" ".sa"; do
  path="$target$suffix"
  if [[ -e "$path" ]]; then
    rm -f "$path"
    printf 'Deleted %s\n' "$path"
    deleted=true
  fi
done

short="${target%.*}"
for suffix in ".dict"; do
  path="$short$suffix"
  if [[ -e "$path" ]]; then
    rm -f "$path"
    printf 'Deleted %s\n' "$path"
    deleted=true
  fi
done

if [[ "$deleted" != "true" ]]; then
  printf 'No files found for %s\n' "$target" >&2
fi
