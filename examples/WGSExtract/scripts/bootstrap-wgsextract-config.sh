#!/bin/sh
set -eu

workspace="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
config_path="${GUI_FOR_CLI_CONFIG_PATH:-$workspace/settings/config.toml}"
output_path="$workspace/output"
reference_path="$workspace/reference"

printf '{\n'
printf '  "path": "%s",\n' "$(printf '%s' "$config_path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '  "contents": "output_directory = \\"%s\\"\\nreference_library = \\"%s\\"\\nreference_fasta = \\"\\"\\ndefault_input_vcf = \\"\\"\\nmother_vcf_path = \\"\\"\\nfather_vcf_path = \\"\\"\\nyleaf_executable = \\"\\"\\nhaplogrep_executable = \\"\\"\\n"\n' \
  "$(printf '%s' "$output_path" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
  "$(printf '%s' "$reference_path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '}\n'
