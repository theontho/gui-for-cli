$ErrorActionPreference = "Stop"

$workspace = if ($env:GUI_FOR_CLI_BUNDLE_WORKSPACE) { $env:GUI_FOR_CLI_BUNDLE_WORKSPACE } else { (Get-Location).Path }
$configPath = if ($env:GUI_FOR_CLI_CONFIG_PATH) { $env:GUI_FOR_CLI_CONFIG_PATH } else { Join-Path $workspace "settings\config.toml" }
$outputPath = Join-Path $workspace "output"
$referencePath = Join-Path $workspace "reference"

[ordered]@{
    path = $configPath
    contents = "output_directory = `"$outputPath`"`nreference_library = `"$referencePath`"`nreference_fasta = `"`"`ndefault_input_vcf = `"`"`nmother_vcf_path = `"`"`nfather_vcf_path = `"`"`nyleaf_executable = `"`"`nhaplogrep_executable = `"`"`n"
} | ConvertTo-Json -Compress
