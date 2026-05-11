#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

port="${PORT:-8787}"
host="${HOST:-127.0.0.1}"
bundle="${BUNDLE:-$repo_root/Examples/WGSExtract}"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid"
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

npm --prefix WebUI run build

node WebUI/dist/server/main.js \
  --bundle "$bundle" \
  --host "$host" \
  --port "$port" &
server_pid="$!"

manifest_url="http://$host:$port/api/manifest"
until curl -fsS "$manifest_url" >/dev/null; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "WebUI backend exited before becoming ready." >&2
    exit 1
  fi
  sleep 0.5
done

GUI_FOR_CLI_REACT_NATIVE_API_BASE="http://$host:$port" \
  npm --prefix Apps/ReactNative/GUIForCLIReactNative run macos
