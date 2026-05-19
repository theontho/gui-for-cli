#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-macos-cold-install-uninstall.sh [options]

Mount a macOS DMG, perform a cold install, launch once with an isolated HOME,
then uninstall the app and app data.

Options:
  --dmg PATH              DMG to test. Default: newest out/release/swiftui/WGSExtract*.dmg
  --install-dir PATH      Install directory. Default: tmp/macos-cold-install/Applications
  --state-root PATH       Temporary state root. Default: tmp/macos-cold-install
  --timeout SECONDS       Launch readiness timeout. Default: 60
  --app-support-name NAME App support container name. Default: unique cold-install test name.
  --bundle-app-support-name
                          Use the app bundle id as the app support name.
  --system-applications   Install into /Applications. This may delete an existing app with the same name.
  --real-home             Use the real HOME for process HOME instead of an isolated temporary HOME.
  --reset-real-app-data   Allow deleting an existing real app support directory for the selected support name.
  --keep                  Keep temporary install/state files after the test.
  -h, --help              Show this help.

Environment overrides:
  DMG_PATH, INSTALL_DIR, STATE_ROOT, LAUNCH_TIMEOUT_SECONDS
EOF
}

log() { printf '[macos-cold-install] %s\n' "$*"; }
fail() { printf '[macos-cold-install] error: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_dmg_path() {
  local release_dir="$repo_root/out/release/swiftui"
  local candidate=""
  candidate="$(
    find "$release_dir" -maxdepth 1 -type f -name 'WGSExtract*.dmg' \
      -exec stat -f '%m %N' {} \; 2>/dev/null \
      | sort -nr \
      | sed -n '1s/^[0-9][0-9]* //p'
  )"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return
  fi
  printf '%s\n' "$release_dir/WGSExtract.dmg"
}

dmg_path="${DMG_PATH:-$(default_dmg_path)}"
install_dir="${INSTALL_DIR:-$repo_root/tmp/macos-cold-install/Applications}"
state_root="${STATE_ROOT:-$repo_root/tmp/macos-cold-install}"
launch_timeout="${LAUNCH_TIMEOUT_SECONDS:-60}"
use_system_applications=0
use_real_home=0
reset_real_app_data=0
keep=0
app_support_name=""
app_support_name_was_custom=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg)
      [ "$#" -ge 2 ] || fail "Missing value for --dmg."
      dmg_path="$2"
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || fail "Missing value for --install-dir."
      install_dir="$2"
      shift 2
      ;;
    --state-root)
      [ "$#" -ge 2 ] || fail "Missing value for --state-root."
      state_root="$2"
      shift 2
      ;;
    --timeout)
      [ "$#" -ge 2 ] || fail "Missing value for --timeout."
      launch_timeout="$2"
      shift 2
      ;;
    --app-support-name)
      [ "$#" -ge 2 ] || fail "Missing value for --app-support-name."
      app_support_name="$2"
      app_support_name_was_custom=1
      shift 2
      ;;
    --bundle-app-support-name)
      app_support_name="__BUNDLE_ID__"
      app_support_name_was_custom=1
      shift
      ;;
    --system-applications)
      use_system_applications=1
      install_dir="/Applications"
      shift
      ;;
    --real-home)
      use_real_home=1
      shift
      ;;
    --reset-real-app-data)
      reset_real_app_data=1
      shift
      ;;
    --keep)
      keep=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || fail "This test only runs on macOS."
case "$launch_timeout" in
  '' | *[!0-9]*) fail "--timeout must be an integer number of seconds." ;;
esac

require_command hdiutil
require_command open
require_command osascript
require_command plutil
require_command codesign
require_command spctl
require_command ditto

dmg_path="$(cd "$(dirname "$dmg_path")" && pwd)/$(basename "$dmg_path")"
[ -f "$dmg_path" ] || fail "DMG not found: $dmg_path"

state_root="$(mkdir -p "$state_root" && cd "$state_root" && pwd)"
mount_root="$state_root/mount"
test_home="$state_root/home"
benchmark_output="$state_root/content-ready.log"
mounted=0
installed_app=""
app_support_dir=""
app_bundle_id=""

app_pids() {
  if [ -z "$installed_app" ]; then
    return
  fi
  ps ax -o pid= -o command= | awk -v needle="$installed_app/Contents/MacOS/" 'index($0, needle) { print $1 }'
}

quit_app() {
  if [ -n "$app_bundle_id" ]; then
    osascript -e "tell application id \"$app_bundle_id\" to quit" >/dev/null 2>&1 || true
  fi
  local deadline=$((SECONDS + 10))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -z "$(app_pids)" ]; then
      return
    fi
    sleep 1
  done
  local pid
  for pid in $(app_pids); do
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 2
  for pid in $(app_pids); do
    kill -9 "$pid" >/dev/null 2>&1 || true
  done
}

cleanup() {
  quit_app
  if [ "$mounted" -eq 1 ]; then
    hdiutil detach "$mount_root" >/dev/null 2>&1 || true
  fi
  if [ "$keep" -eq 0 ] && [ "$use_system_applications" -eq 0 ]; then
    rm -rf "$state_root"
  fi
}
trap cleanup EXIT INT HUP TERM

rm -rf "$mount_root"
mkdir -p "$mount_root"
log "Mounting $dmg_path"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_root" "$dmg_path" >/dev/null
mounted=1

mounted_app_count="$(find "$mount_root" -maxdepth 1 -name '*.app' -type d | wc -l | tr -d ' ')"
[ "$mounted_app_count" -eq 1 ] || fail "Expected exactly one .app in the DMG, found $mounted_app_count."
mounted_app="$(find "$mount_root" -maxdepth 1 -name '*.app' -type d | sort | sed -n '1p')"
app_name="$(basename "$mounted_app")"
installed_app="$install_dir/$app_name"
info_plist="$mounted_app/Contents/Info.plist"
[ -f "$info_plist" ] || fail "Missing app Info.plist: $info_plist"
app_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
[ -n "$app_bundle_id" ] || fail "Could not read CFBundleIdentifier from $info_plist"
if [ -z "$app_support_name" ]; then
  app_support_name="$app_bundle_id.cold-install-test.$$"
elif [ "$app_support_name" = "__BUNDLE_ID__" ]; then
  app_support_name="$app_bundle_id"
fi

test -L "$mount_root/Applications" || fail "DMG is missing the /Applications symlink."
if [ -f "$mount_root/.background/installer.png" ] && [ -f "$mount_root/.DS_Store" ]; then
  log "Verified custom Finder background and layout metadata."
elif [ ! -e "$mount_root/.background/installer.png" ] && [ ! -e "$mount_root/.DS_Store" ]; then
  log "DMG uses the default Finder presentation."
else
  fail "DMG has partial Finder presentation metadata; expected both .background/installer.png and .DS_Store, or neither."
fi

if [ "$use_system_applications" -eq 0 ] && [ "$install_dir" = "/Applications" ]; then
  fail "Refusing to install into /Applications without --system-applications."
fi

if [ "$use_real_home" -eq 1 ]; then
  app_home="$HOME"
else
  rm -rf "$test_home"
  mkdir -p "$test_home"
  app_home="$test_home"
fi
app_support_dir="$HOME/Library/Application Support/$app_support_name"

if [ "$app_support_name_was_custom" -eq 1 ] && [ -d "$app_support_dir" ] && [ "$reset_real_app_data" -ne 1 ]; then
  fail "Refusing to delete existing app data without --reset-real-app-data: $app_support_dir"
fi

log "Removing previous install and app data"
rm -rf "$installed_app" "$app_support_dir"
mkdir -p "$install_dir"

log "Installing $app_name to $install_dir"
ditto "$mounted_app" "$installed_app"
test -d "$installed_app" || fail "Install did not create $installed_app"

signature_info="$state_root/code-signature.txt"
if codesign -dv --verbose=2 "$installed_app" >"$signature_info" 2>&1 \
  && grep -q '^Authority=' "$signature_info"; then
  log "Verifying code signature"
  codesign --verify --deep --strict --verbose=2 "$installed_app"
  if grep -q '^Authority=Developer ID Application:' "$signature_info"; then
    log "Verifying Gatekeeper assessment"
    spctl --assess --type execute --verbose=2 "$installed_app"
  else
    log "Skipping Gatekeeper assessment for non-Developer ID signature."
  fi
else
  log "App has no signing authority; skipping signature and Gatekeeper checks."
fi

log "Launching cold app with HOME=$app_home"
rm -f "$benchmark_output"
open -n -g \
  --env "HOME=$app_home" \
  --env "GUI_FOR_CLI_APP_SUPPORT_NAME=$app_support_name" \
  --env "GFC_BENCHMARK_STARTUP=1" \
  --env "GFC_BENCHMARK_OUTPUT=$benchmark_output" \
  "$installed_app"

deadline=$((SECONDS + launch_timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$benchmark_output" ]; then
    break
  fi
  sleep 1
done
test -s "$benchmark_output" || fail "App did not report content readiness within ${launch_timeout}s."
test -d "$app_support_dir" || fail "App did not create app support directory: $app_support_dir"
test -d "$app_support_dir/BundleWorkspaces" || fail "App did not create BundleWorkspaces under app support."

log "Quitting app"
quit_app

log "Uninstalling app and app data"
rm -rf "$installed_app" "$app_support_dir"
test ! -e "$installed_app" || fail "Installed app still exists after uninstall: $installed_app"
test ! -e "$app_support_dir" || fail "App data still exists after uninstall: $app_support_dir"

log "Cold install/uninstall loop passed for $app_name ($app_bundle_id)."
