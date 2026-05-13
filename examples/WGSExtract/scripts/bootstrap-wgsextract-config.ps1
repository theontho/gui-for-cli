$ErrorActionPreference = "Stop"

$workspace = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$configPath = if ($env:GUI_FOR_CLI_CONFIG_PATH) { $env:GUI_FOR_CLI_CONFIG_PATH } else { Join-Path $workspace "settings\config.toml" }

[ordered]@{
    path = $configPath
    contents = "output_directory = `"`"`nreference_library = `"`"`nreference_fasta = `"`"`ndefault_input_vcf = `"`"`nmother_vcf_path = `"`"`nfather_vcf_path = `"`"`nyleaf_executable = `"`"`nhaplogrep_executable = `"`"`n"
} | ConvertTo-Json -Compress
