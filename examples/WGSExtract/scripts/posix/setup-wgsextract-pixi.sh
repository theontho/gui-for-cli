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
INSTALL_DIR="${WGSEXTRACT_INSTALL_DIR:-$(pwd)/runtime/wgsextract-cli}"
APP_DIR="$INSTALL_DIR/app"
BIN_DIR="$INSTALL_DIR/bin"
PIXI_ENV_DIR="${WGSEXTRACT_PIXI_ENV_DIR:-$APP_DIR/.pixi/envs}"

log() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
download_with_retry() {
  url="$1"
  output="$2"
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors -o "$output" "$url"
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
    return 0
  fi
  if [ -n "$fallback_url" ] && [ "$fallback_url" != "$primary_url" ]; then
    log "Primary source archive download failed; downloading from $fallback_url"
    download_with_retry "$fallback_url" "$output"
    return 0
  fi
  return 1
}

pixi_asset_name() {
  platform="$(uname -s)"
  arch="${PIXI_ARCH:-$(uname -m)}"
  case "$platform" in
    Darwin) platform="apple-darwin" ;;
    Linux)
      if [ "$arch" = "riscv64" ]; then
        platform="unknown-linux-gnu"
      else
        platform="unknown-linux-musl"
      fi
      ;;
    *) fail "Unsupported Pixi install platform: $platform" ;;
  esac
  case "$arch" in
    arm64 | aarch64) arch="aarch64" ;;
    riscv64) arch="riscv64gc" ;;
  esac
  printf 'pixi-%s-%s.tar.gz' "$arch" "$platform"
}

install_pixi_with_retry() {
  version="${PIXI_VERSION:-latest}"
  repo_url="${PIXI_REPOURL:-https://github.com/prefix-dev/pixi}"
  pixi_home="${PIXI_HOME:-$INSTALL_DIR/.pixi}"
  case "$pixi_home" in
    "~" | "~"/*) pixi_home="$HOME${pixi_home#\~}" ;;
  esac
  pixi_bin_dir="${PIXI_BIN_DIR:-$pixi_home/bin}"
  asset_name="$(pixi_asset_name)"
  if [ "$version" = "latest" ]; then
    pixi_url="${PIXI_DOWNLOAD_URL:-${repo_url%/}/releases/latest/download/$asset_name}"
  else
    pixi_url="${PIXI_DOWNLOAD_URL:-${repo_url%/}/releases/download/v${version#v}/$asset_name}"
  fi

  log "Downloading Pixi from $pixi_url"
  pixi_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixi-install.XXXXXX")"
  pixi_archive="$pixi_work_dir/$asset_name"
  pixi_extract_dir="$pixi_work_dir/pixi"
  mkdir -p "$pixi_extract_dir" "$pixi_bin_dir"
  if download_with_retry "$pixi_url" "$pixi_archive"; then
    tar -xzf "$pixi_archive" -C "$pixi_extract_dir"
    pixi_binary="$(find "$pixi_extract_dir" -type f -name pixi | head -n 1)"
    [ -n "$pixi_binary" ] || fail "Downloaded Pixi archive did not contain a pixi binary."
    mv "$pixi_binary" "$pixi_bin_dir/pixi"
  else
    pixi_binary_url="${pixi_url%.tar.gz}"
    log "Pixi archive download failed; downloading raw binary from $pixi_binary_url"
    download_with_retry "$pixi_binary_url" "$pixi_bin_dir/pixi"
  fi
  chmod +x "$pixi_bin_dir/pixi"
  rm -rf "$pixi_work_dir"
  PIXI="$pixi_bin_dir/pixi"
}

command_exists curl || fail "curl is required."
command_exists tar || fail "tar is required."
command_exists gzip || fail "gzip is required."

PIXI="${PIXI:-}"
PIXI_INSTALLED_BY_SETUP=0
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
    install_pixi_with_retry
    PIXI_INSTALLED_BY_SETUP=1
    if [ -n "$PIXI" ] && [ -x "$PIXI" ]; then
      :
    elif [ -x "$HOME/.pixi/bin/pixi" ]; then
      PIXI="$HOME/.pixi/bin/pixi"
    elif command_exists pixi; then
      PIXI="$(command -v pixi)"
    else
      fail "Pixi installation completed, but pixi was not found."
    fi
  fi
fi

ARCHIVE_FALLBACK_URL=""
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
  ARCHIVE_FALLBACK_URL="$(github_codeload_url "$REPO_URL" "$REF" || true)"
fi

mkdir -p "$INSTALL_DIR/tmp" "$PIXI_ENV_DIR" "$BIN_DIR"
work_dir="$(mktemp -d "$INSTALL_DIR/tmp/install.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT HUP TERM
archive="$work_dir/wgsextract-cli.tar.gz"
extract_dir="$work_dir/source"
mkdir -p "$extract_dir"

log "Downloading WGS Extract CLI from $ARCHIVE_URL"
download_source_archive "$ARCHIVE_URL" "$ARCHIVE_FALLBACK_URL" "$archive"
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
if [ "${WGSEXTRACT_PIXI_CACHE_DIR:-}" ]; then
  PIXI_CACHE_DIR="$WGSEXTRACT_PIXI_CACHE_DIR"
  export PIXI_CACHE_DIR
  mkdir -p "$PIXI_CACHE_DIR"
elif [ "$PIXI_INSTALLED_BY_SETUP" = "1" ]; then
  PIXI_CACHE_DIR="$INSTALL_DIR/.pixi/cache"
  export PIXI_CACHE_DIR
  mkdir -p "$PIXI_CACHE_DIR"
fi
export PIXI_PROJECT_ENVIRONMENT_DIR="$PIXI_ENV_DIR"
"$PIXI" install
"$PIXI" run wgsextract --help >/dev/null
"$PIXI" run wgsextract deps check

wgsextract_bin=""
for candidate in "$PIXI_ENV_DIR/default/bin/wgsextract" "$APP_DIR/.pixi/envs/default/bin/wgsextract"; do
  if [ -x "$candidate" ]; then
    wgsextract_bin="$candidate"
    break
  fi
done
[ -n "$wgsextract_bin" ] || fail "Expected wgsextract binary not found in $PIXI_ENV_DIR/default/bin or $APP_DIR/.pixi/envs/default/bin"
ln -sf "$wgsextract_bin" "$BIN_DIR/wgsextract"

log "WGS Extract CLI is installed in $INSTALL_DIR"
