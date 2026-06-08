#!/bin/sh
set -eu

REPO_URL="${WGSEXTRACT_REPO_URL:-https://github.com/theontho/wgsextract-cli}"
script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
release_tag_file="${WGSEXTRACT_RELEASE_TAG_FILE:-$script_dir/../wgsextract-release-tag.txt}"
DEFAULT_RELEASE_TAG="${WGSEXTRACT_DEFAULT_RELEASE_TAG:-}"
if [ -z "$DEFAULT_RELEASE_TAG" ] && [ -f "$release_tag_file" ]; then
  DEFAULT_RELEASE_TAG="$(sed -n '1s/[[:space:]]*$//p' "$release_tag_file")"
fi
DEFAULT_RELEASE_TAG="${DEFAULT_RELEASE_TAG:-latest}"
REQUESTED_REF="${WGSEXTRACT_REF:-${WGSEXTRACT_RELEASE_TAG:-$DEFAULT_RELEASE_TAG}}"

bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(CDPATH= cd "$script_dir/../.." && pwd)}"
INSTALL_DIR="${WGSEXTRACT_INSTALL_DIR:-$bundle_root/runtime/wgsextract-cli}"
APP_DIR="$INSTALL_DIR/app"
BIN_DIR="$INSTALL_DIR/bin"

log() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

download_with_retry() {
  url="$1"
  output="$2"

  if [ -f "$url" ]; then
    cp "$url" "$output"
    return
  fi

  curl -fsSL --retry 5 --retry-delay 2 -o "$output" "$url"
}

github_codeload_url() {
  repo_url="$1"
  ref="$2"
  case "$repo_url" in
    https://github.com/*/*)
      repo_path="${repo_url#https://github.com/}"
      repo_path="${repo_path%.git}"
      owner="${repo_path%%/*}"
      repo_name="${repo_path#*/}"
      repo_name="${repo_name%%/*}"
      printf 'https://codeload.github.com/%s/%s/tar.gz/%s\n' "$owner" "$repo_name" "$ref"
      ;;
    *)
      return 1
      ;;
  esac
}

download_source_archive() {
  primary_url="$1"
  fallback_url="${2:-}"
  output="$3"

  if download_with_retry "$primary_url" "$output"; then
    return
  fi
  if [ -n "$fallback_url" ] && [ "$fallback_url" != "$primary_url" ]; then
    log "Primary source archive download failed; downloading from $fallback_url"
    download_with_retry "$fallback_url" "$output"
    return
  fi
  return 1
}

resolve_archive_urls() {
  if [ "${WGSEXTRACT_ARCHIVE_URL:-}" ]; then
    REF="${REQUESTED_REF:-custom}"
    ARCHIVE_URL="$WGSEXTRACT_ARCHIVE_URL"
    ARCHIVE_FALLBACK_URL=""
    return
  fi

  [ -n "$REPO_URL" ] || fail "Set WGSEXTRACT_REPO_URL or WGSEXTRACT_ARCHIVE_URL before running setup."
  case "$REQUESTED_REF" in
    ""|latest)
      latest_url="$REPO_URL/releases/latest"
      effective_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' "$latest_url")" || fail "Could not resolve latest release."
      REF="${effective_url##*/}"
      ;;
    *)
      REF="$REQUESTED_REF"
      ;;
  esac
  ARCHIVE_URL="$REPO_URL/archive/$REF.tar.gz"
  ARCHIVE_FALLBACK_URL="$(github_codeload_url "$REPO_URL" "$REF" || true)"
}

command_exists curl || fail "curl is required."
command_exists tar || fail "tar is required."
command_exists gzip || fail "gzip is required."

resolve_archive_urls

mkdir -p "$INSTALL_DIR/tmp"
work_dir="$(mktemp -d "$INSTALL_DIR/tmp/bootstrap.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT HUP TERM

archive="$work_dir/wgsextract-cli.tar.gz"
extract_dir="$work_dir/source"
mkdir -p "$extract_dir"

log "Downloading WGS Extract CLI from $ARCHIVE_URL"
download_source_archive "$ARCHIVE_URL" "$ARCHIVE_FALLBACK_URL" "$archive"
tar -xzf "$archive" -C "$extract_dir"
source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$source_dir" ] || fail "Downloaded archive did not contain a source directory."

installer="$source_dir/install.sh"
[ -f "$installer" ] || fail "Downloaded archive did not contain install.sh."
sh -n "$installer" || fail "Downloaded install.sh failed shell syntax validation."

export WGSEXTRACT_INSTALL_DIR="$INSTALL_DIR"
export WGSEXTRACT_BIN_DIR="$BIN_DIR"
export WGSEXTRACT_PIXI_HOME="${WGSEXTRACT_PIXI_HOME:-$INSTALL_DIR/.pixi}"
export WGSEXTRACT_PIXI_CACHE_DIR="${WGSEXTRACT_PIXI_CACHE_DIR:-$INSTALL_DIR/.pixi/cache}"
export WGSEXTRACT_PIXI_ENV_DIR="${WGSEXTRACT_PIXI_ENV_DIR:-$APP_DIR/.pixi/envs}"
export WGSEXTRACT_ARCHIVE_URL="$archive"
export WGSEXTRACT_REF="$REF"
export WGSEXTRACT_NO_OPEN=1

log "Delegating WGS Extract CLI install to upstream install.sh..."
sh "$installer"
