#!/bin/sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
bundle_root="${GUI_FOR_CLI_BUNDLE_WORKSPACE:-$(CDPATH= cd "$script_dir/../.." && pwd)}"
runtime="$bundle_root/runtime/wgsextract-cli"
manifest_path="$runtime/install-manifest.json"

strip_path_entry() {
  # Strip $1 from the user's shell rc PATH exports we control. We can't
  # mutate child shells' environments, but we can clean common rc files
  # the pixi installer writes (~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish).
  entry="$1"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.config/fish/config.fish"; do
    [ -f "$rc" ] || continue
    # Remove any line that adds the entry to PATH (covers pixi installer's exports).
    tmp="$(mktemp "${rc}.uninstallXXXXXX")"
    if grep -v -F "$entry" "$rc" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$rc"
    else
      rm -f "$tmp"
    fi
  done
}

apply_manifest_items() {
  [ -f "$manifest_path" ] || return 0
  # Minimal JSON traversal without jq: extract items via python3 if available, fall back to grep.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$manifest_path" <<'PY'
import json, os, shutil, subprocess, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        manifest = json.load(fh)
except Exception as exc:
    print(f"Could not parse install manifest at {path}: {exc}", file=sys.stderr)
    sys.exit(0)
for item in manifest.get("items", []) or []:
    kind = item.get("type")
    if kind == "directory":
        target = item.get("path")
        if target and os.path.exists(target):
            try:
                shutil.rmtree(target, ignore_errors=False)
                print(f"Removed directory: {target}")
            except OSError as exc:
                print(f"Warning: could not remove {target}: {exc}", file=sys.stderr)
    elif kind == "userPathEntry":
        target = item.get("path")
        if target:
            # Print a marker line the shell wrapper consumes to update rc files.
            print(f"__PATH_ENTRY_TO_STRIP__\t{target}")
    elif kind == "msys2Package":
        # POSIX hosts don't run pacman in the MSYS2 sense; ignore.
        continue
    else:
        print(f"Warning: unknown install-manifest item type '{kind}'; skipping.", file=sys.stderr)
PY
  else
    printf 'Warning: python3 not available; install-manifest items at %s were not processed.\n' "$manifest_path" >&2
    return 0
  fi
}

if [ -f "$manifest_path" ]; then
  apply_manifest_items | while IFS= read -r line; do
    case "$line" in
      __PATH_ENTRY_TO_STRIP__*)
        entry="${line#__PATH_ENTRY_TO_STRIP__	}"
        strip_path_entry "$entry"
        printf 'Removed shell rc PATH references to: %s\n' "$entry"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
fi

if [ -e "$runtime" ]; then
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "$runtime" 2>/dev/null || true
  fi
  rm -rf "$runtime"
fi
printf 'Removed WGS Extract runtime: %s\n' "$runtime"
