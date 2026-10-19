# Where WGS Extract's MSYS2 is (dot-source this file): setup installs it there
# unless one already is, commands find their tools there, and uninstall removes
# it if setup installed it. WGSEXTRACT_MSYS2_ROOT overrides it.
function Get-WGSExtractMsys2Root {
    if ($env:WGSEXTRACT_MSYS2_ROOT) { return $env:WGSEXTRACT_MSYS2_ROOT }
    return Join-Path $env:LOCALAPPDATA "msys64"
}
