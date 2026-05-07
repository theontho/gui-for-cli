#!/bin/sh
set -eu

config_path="${GUI_FOR_CLI_CONFIG_PATH:-${HOME}/.config/wgsextract/config.toml}"

printf '{\n'
printf '  "path": "%s",\n' "$(printf '%s' "$config_path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '  "contents": "output_directory = \\"\\"\\nreference_library = \\"\\"\\nreference_fasta = \\"\\"\\ndefault_input_vcf = \\"\\"\\nmother_vcf_path = \\"\\"\\nfather_vcf_path = \\"\\"\\nyleaf_executable = \\"\\"\\nhaplogrep_executable = \\"\\"\\n"\n'
printf '}\n'
