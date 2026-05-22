#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(pwd)}"
reference_library="${WGSEXTRACT_REFERENCE_LIBRARY:-$bundle_root/reference}"

install_mappability_maps() {
  if command -v python3 >/dev/null 2>&1; then
    WGSEXTRACT_REFERENCE_LIBRARY="$reference_library" python3 - <<'PY'
import hashlib
import os
import shutil
import sys
import urllib.request
import zipfile

url = os.environ.get(
    "WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_URL",
    "https://github.com/theontho/wgsextract-cli/releases/download/v0.1.0/wgsextract-delly-mappability-maps.zip",
)
expected_sha = os.environ.get(
    "WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE_SHA256",
    "cab55d8fe28f3c0da90cfdd0a8a4951dc5a33d182bbce3ef34392762eafe5d1b",
)
reference_library = os.environ["WGSEXTRACT_REFERENCE_LIBRARY"]
archive_override = os.environ.get("WGSEXTRACT_MAPPABILITY_MAP_ARCHIVE", "")
files = (
    "hg19.map.gz",
    "hg19.map.gz.fai",
    "hg19.map.gz.gzi",
    "hg38.map.gz",
    "hg38.map.gz.fai",
    "hg38.map.gz.gzi",
)
maps_dir = os.path.join(reference_library, "maps")
os.makedirs(maps_dir, exist_ok=True)
if all(os.path.isfile(os.path.join(maps_dir, name)) for name in files):
    print("Delly mappability maps are already installed.")
    raise SystemExit(0)

archive_path = archive_override or os.path.join(reference_library, "wgsextract-delly-mappability-maps.zip")
remove_archive = not archive_override
if archive_override:
    print(f"Using Delly mappability map archive: {archive_path}")
elif url.startswith(("http://", "https://")):
    print(f"Downloading Delly mappability maps from {url}...")
    urllib.request.urlretrieve(url, archive_path)
else:
    print(f"Copying Delly mappability maps from {url}...")
    shutil.copyfile(url, archive_path)

try:
    if expected_sha:
        digest = hashlib.sha256()
        with open(archive_path, "rb") as archive_file:
            for chunk in iter(lambda: archive_file.read(1024 * 1024), b""):
                digest.update(chunk)
        actual_sha = digest.hexdigest()
        if actual_sha.lower() != expected_sha.lower():
            print(
                f"Mappability map archive SHA256 mismatch: expected {expected_sha}, got {actual_sha}",
                file=sys.stderr,
            )
            raise SystemExit(1)
        print(f"Verified GitHub release asset SHA256: {actual_sha}")

    print(f"Extracting Delly mappability maps to {maps_dir}...")
    with zipfile.ZipFile(archive_path) as archive:
        members = {name.replace("\\", "/"): name for name in archive.namelist()}
        for file_name in files:
            member = members.get(f"maps/{file_name}")
            if not member:
                print(f"Mappability map archive is missing maps/{file_name}.", file=sys.stderr)
                raise SystemExit(1)
            target = os.path.join(maps_dir, file_name)
            with archive.open(member) as source, open(target, "wb") as destination:
                shutil.copyfileobj(source, destination)
    print("Delly mappability maps are installed.")
finally:
    if remove_archive:
        try:
            os.remove(archive_path)
        except OSError:
            pass
PY
  else
    printf '%s\n' "python3 is required to install Delly mappability maps." >&2
    return 1
  fi
}

set -- ref bootstrap --ref "$reference_library"

sh "$script_dir/run-wgsextract.sh" "$@"
bootstrap_status=$?
if [ "$bootstrap_status" -ne 0 ]; then
  exit "$bootstrap_status"
fi

if [ "${WGSEXTRACT_SKIP_MAPPABILITY_MAPS:-}" != "1" ]; then
  install_mappability_maps
fi
