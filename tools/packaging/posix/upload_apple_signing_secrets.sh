#!/bin/sh
# Upload this Mac's Developer ID signing identity to the repo's GitHub secrets,
# so the Distribution workflow can sign and notarize without this machine.
#
# Usage: tools/packaging/posix/upload_apple_signing_secrets.sh [--repo OWNER/NAME]
#
# Exports only the "Developer ID Application" identity (macOS asks you to allow
# the export), re-packs it as a .p12 with a fresh random password, and sets
# APPLE_CERTIFICATE_P12 / APPLE_CERTIFICATE_PASSWORD. Nothing secret is printed,
# and the temporary files are removed on exit.
set -eu

repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
set -- ${repo:+--repo "$repo"}

command -v gh >/dev/null 2>&1 || { echo "gh (GitHub CLI) is required." >&2; exit 1; }
identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sort -u)"
[ -n "$identity" ] || { echo "No Developer ID Application identity in the keychain." >&2; exit 1; }
[ "$(printf '%s\n' "$identity" | wc -l)" -eq 1 ] || {
  printf 'Several Developer ID Application identities; keep one:\n%s\n' "$identity" >&2
  exit 1
}

umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT HUP TERM
export_password="$(openssl rand -hex 24)"
password="$(openssl rand -hex 24)"

echo "Exporting signing identities (allow the export when macOS asks)..."
security export -k "$HOME/Library/Keychains/login.keychain-db" -t identities -f pkcs12 \
  -P "$export_password" -o "$work/all.p12"

# Keep only the Developer ID key and certificate.
openssl pkcs12 -in "$work/all.p12" -passin "pass:$export_password" -nodes -out "$work/all.pem" 2>/dev/null ||
  openssl pkcs12 -legacy -in "$work/all.p12" -passin "pass:$export_password" -nodes -out "$work/all.pem"
python3 "$(dirname "$0")/select_p12_identity.py" "$work/all.pem" "$identity" "$work/key.pem" "$work/cert.pem"

# 3DES/SHA1 so the runner's `security import` accepts it.
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$identity" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$password" -out "$work/devid.p12"

base64 < "$work/devid.p12" | tr -d '\n' | gh secret set APPLE_CERTIFICATE_P12 "$@"
printf '%s' "$password" | gh secret set APPLE_CERTIFICATE_PASSWORD "$@"
printf '%s' "$identity" | gh secret set APPLE_SIGNING_IDENTITY "$@"
echo "Uploaded \"$identity\" to GitHub secrets."
