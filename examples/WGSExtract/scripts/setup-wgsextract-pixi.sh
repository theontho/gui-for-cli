#!/bin/sh
set -eu

REPO_URL="${WGSEXTRACT_REPO_URL:-https://github.com/theontho/wgsextract-cli}"
REQUESTED_REF="${WGSEXTRACT_REF:-${WGSEXTRACT_RELEASE_TAG:-latest}}"
INSTALL_DIR="${WGSEXTRACT_INSTALL_DIR:-$(pwd)/runtime/wgsextract-cli}"
APP_DIR="$INSTALL_DIR/app"
BIN_DIR="$INSTALL_DIR/bin"
PIXI_CACHE_DIR="${WGSEXTRACT_PIXI_CACHE_DIR:-$INSTALL_DIR/.pixi/cache}"
PIXI_ENV_DIR="${WGSEXTRACT_PIXI_ENV_DIR:-$INSTALL_DIR/.pixi/envs}"

log() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

command_exists curl || fail "curl is required."
command_exists tar || fail "tar is required."
command_exists gzip || fail "gzip is required."

PIXI="${PIXI:-}"
if [ -n "$PIXI" ] && [ ! -x "$PIXI" ]; then
  fail "PIXI is set but is not executable: $PIXI"
fi
if [ -z "$PIXI" ]; then
  if command_exists pixi; then
    PIXI="$(command -v pixi)"
  elif [ -x "$HOME/.pixi/bin/pixi" ]; then
    PIXI="$HOME/.pixi/bin/pixi"
  else
    log "Installing Pixi..."
    curl -fsSL https://pixi.sh/install.sh | sh
    if [ -x "$HOME/.pixi/bin/pixi" ]; then
      PIXI="$HOME/.pixi/bin/pixi"
    elif command_exists pixi; then
      PIXI="$(command -v pixi)"
    else
      fail "Pixi installation completed, but pixi was not found."
    fi
  fi
fi

if [ "${WGSEXTRACT_ARCHIVE_URL:-}" ]; then
  ARCHIVE_URL="$WGSEXTRACT_ARCHIVE_URL"
else
  [ -n "$REPO_URL" ] || fail "Set WGSEXTRACT_REPO_URL or WGSEXTRACT_ARCHIVE_URL before running setup."
  if [ "$REQUESTED_REF" = "latest" ] || [ -z "$REQUESTED_REF" ]; then
    latest_url="$REPO_URL/releases/latest"
    effective_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' "$latest_url")" || fail "Could not resolve latest release."
    REF="${effective_url##*/}"
  else
    REF="$REQUESTED_REF"
  fi
  ARCHIVE_URL="$REPO_URL/archive/$REF.tar.gz"
fi

mkdir -p "$INSTALL_DIR/tmp" "$PIXI_CACHE_DIR" "$PIXI_ENV_DIR" "$BIN_DIR"
work_dir="$(mktemp -d "$INSTALL_DIR/tmp/install.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT HUP TERM
archive="$work_dir/wgsextract-cli.tar.gz"
extract_dir="$work_dir/source"
mkdir -p "$extract_dir"

log "Downloading WGS Extract CLI from $ARCHIVE_URL"
curl -fL --retry 3 --retry-delay 2 -o "$archive" "$ARCHIVE_URL"
tar -xzf "$archive" -C "$extract_dir"
source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$source_dir" ] || fail "Downloaded archive did not contain a source directory."

rm -rf "$APP_DIR.new"
mkdir -p "$INSTALL_DIR"
mv "$source_dir" "$APP_DIR.new"
rm -rf "$APP_DIR"
mv "$APP_DIR.new" "$APP_DIR"

log "Installing Pixi environment..."
cd "$APP_DIR"
export PIXI_CACHE_DIR
export PIXI_PROJECT_ENVIRONMENT_DIR="$PIXI_ENV_DIR"
"$PIXI" install
"$PIXI" run wgsextract --help >/dev/null
"$PIXI" run wgsextract deps check

ln -sf ../.pixi/envs/default/bin/wgsextract "$BIN_DIR/wgsextract"

log "WGS Extract CLI is installed in $INSTALL_DIR"
