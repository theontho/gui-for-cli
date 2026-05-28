#!/usr/bin/env bash
set -euo pipefail

# End-to-end validation that mounts the SwiftUI DMG, installs the app, runs
# BAM/VCF actions through the bundle test runner against a stubbed
# WGSExtract CLI, records the screen, then uninstalls.

usage() {
  cat <<'EOF'
Usage: scripts/validate-macos-action-e2e.sh [options]

Options:
  --dmg PATH        DMG to install. Default: newest out/release/swiftui/WGSExtract*.dmg
  --state-root PATH Temporary state root. Default: tmp/macos-action-e2e
  --no-record       Skip screen recording.
  --launch-seconds N
                    Seconds to leave the app on screen during recording. Default: 18
  --keep            Keep temporary files after the test.
  -h, --help        Show this help.
EOF
}

log()  { printf '[macos-action-e2e] %s\n' "$*"; }
fail() { printf '[macos-action-e2e] error: %s\n' "$*" >&2; exit 1; }

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

dmg_path="$(default_dmg_path)"
state_root="$repo_root/tmp/macos-action-e2e"
record=1
launch_seconds=18
keep=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg) [ "$#" -ge 2 ] || fail "Missing --dmg value"; dmg_path="$2"; shift 2 ;;
    --state-root) [ "$#" -ge 2 ] || fail "Missing --state-root value"; state_root="$2"; shift 2 ;;
    --no-record) record=0; shift ;;
    --launch-seconds) [ "$#" -ge 2 ] || fail "Missing --launch-seconds value"; launch_seconds="$2"; shift 2 ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || fail "This test only runs on macOS."
require_command hdiutil
require_command open
require_command osascript
require_command ditto
require_command plutil
require_command swift
require_command ffmpeg
[ -f "$dmg_path" ] || fail "DMG not found: $dmg_path"

state_root="$(mkdir -p "$state_root" && cd "$state_root" && pwd)"
mount_root="$state_root/mount"
install_dir="$state_root/Applications"
test_home="$state_root/home"
fixtures_dir="$state_root/fixtures"
workspace_dir="$state_root/workspace"
stub_bin_dir="$state_root/stub-bin"
video_path="$state_root/wgsextract-action-e2e.mp4"
report_path="$state_root/bundle-test-report.json"
log_path="$state_root/bundle-test-log.txt"
benchmark_output="$state_root/content-ready.log"

mounted=0
installed_app=""
app_bundle_id=""
recorder_pid=""

app_pids() {
  [ -n "$installed_app" ] || return 0
  ps ax -o pid= -o command= | awk -v needle="$installed_app/Contents/MacOS/" 'index($0, needle) { print $1 }'
}

quit_app() {
  [ -n "$app_bundle_id" ] && osascript -e "tell application id \"$app_bundle_id\" to quit" >/dev/null 2>&1 || true
  local deadline=$((SECONDS + 10))
  while [ "$SECONDS" -lt "$deadline" ]; do
    [ -z "$(app_pids)" ] && return
    sleep 1
  done
  local pid
  for pid in $(app_pids); do kill "$pid" >/dev/null 2>&1 || true; done
  sleep 2
  for pid in $(app_pids); do kill -9 "$pid" >/dev/null 2>&1 || true; done
}

stop_recorder() {
  [ -n "$recorder_pid" ] || return 0
  if kill -0 "$recorder_pid" 2>/dev/null; then
    # ffmpeg exits cleanly on 'q' on stdin or SIGINT.
    kill -INT "$recorder_pid" >/dev/null 2>&1 || true
    local deadline=$((SECONDS + 10))
    while [ "$SECONDS" -lt "$deadline" ] && kill -0 "$recorder_pid" 2>/dev/null; do sleep 1; done
    kill -0 "$recorder_pid" 2>/dev/null && kill -9 "$recorder_pid" >/dev/null 2>&1 || true
  fi
  wait "$recorder_pid" 2>/dev/null || true
  recorder_pid=""
}

cleanup() {
  stop_recorder
  quit_app
  [ "$mounted" -eq 1 ] && hdiutil detach "$mount_root" >/dev/null 2>&1 || true
  if [ -d "$install_dir" ]; then
    rm -rf "$installed_app" 2>/dev/null || true
  fi
  if [ "$keep" -eq 0 ]; then
    # Preserve the recorded video and reports even when not keeping the workspace.
    if [ -f "$video_path" ] || [ -f "$report_path" ] || [ -f "$log_path" ]; then
      local artifacts="$repo_root/tmp/macos-action-e2e-artifacts"
      mkdir -p "$artifacts"
      [ -f "$video_path" ] && cp "$video_path" "$artifacts/" || true
      [ -f "$report_path" ] && cp "$report_path" "$artifacts/" || true
      [ -f "$log_path" ] && cp "$log_path" "$artifacts/" || true
      log "Preserved artifacts in $artifacts"
    fi
    rm -rf "$state_root"
  fi
}
trap cleanup EXIT INT HUP TERM

mkdir -p "$mount_root" "$install_dir" "$test_home" "$fixtures_dir" "$workspace_dir" "$stub_bin_dir"

# 1) Create a stub wgsextract CLI so the bundle test runner can execute actions
#    end-to-end without the heavyweight pixi+conda runtime install.
cat > "$stub_bin_dir/wgsextract" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '[wgsextract-stub] argv:'
for arg in "$@"; do printf ' %q' "$arg"; done
printf '\n'
case "${1:-}" in
  info)
    printf '[wgsextract-stub] BAM info report\n'
    printf '  reads:     12345\n'
    printf '  reference: %s\n' "${4:-unknown}"
    ;;
  vcf)
    printf '[wgsextract-stub] VCF %s pipeline\n' "${2:-snp}"
    printf '  variants:  6789\n'
    printf '  outdir:    %s\n' "${@: -1}"
    ;;
  bam)
    printf '[wgsextract-stub] BAM %s\n' "${2:-op}"
    ;;
  *)
    printf '[wgsextract-stub] no-op for: %s\n' "${1:-<empty>}"
    ;;
esac
STUB
chmod +x "$stub_bin_dir/wgsextract"

# 2) Tiny fake BAM input — bundled actions only validate that the path exists,
#    so this content is enough for the stub CLI invocation to succeed.
printf 'fake bam content for e2e test\n' > "$fixtures_dir/sample.bam"

# 3) Mount the DMG and install the app to an isolated /Applications dir.
log "Mounting $dmg_path"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_root" "$dmg_path" >/dev/null
mounted=1
mounted_app="$(find "$mount_root" -maxdepth 1 -name '*.app' -type d | sort | sed -n '1p')"
[ -d "$mounted_app" ] || fail "Could not find .app in mounted DMG."
app_name="$(basename "$mounted_app")"
installed_app="$install_dir/$app_name"
app_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$mounted_app/Contents/Info.plist")"
app_support_name="$app_bundle_id.action-e2e-test.$$"
app_support_dir="$HOME/Library/Application Support/$app_support_name"

log "Installing $app_name to $install_dir"
rm -rf "$installed_app" "$app_support_dir"
ditto "$mounted_app" "$installed_app"

# 4) Start screen recording (best-effort; needs Screen Recording permission).
if [ "$record" -eq 1 ]; then
  screen_device="$({
    ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true
  } | awk '
    /AVFoundation video devices/ { v=1; next }
    /AVFoundation audio devices/ { v=0 }
    v && /Capture screen 0/ && !found {
      if (match($0, /\[[0-9]+\]/)) {
        s = substr($0, RSTART+1, RLENGTH-2)
        print s
        found = 1
      }
    }
  ')"
  if [ -z "$screen_device" ]; then
    log "warn: no avfoundation screen capture device found; recording disabled."
    record=0
  fi
fi
if [ "$record" -eq 1 ]; then
  log "Starting screen recording -> $video_path (device $screen_device)"
  rm -f "$video_path"
  ffmpeg -y -hide_banner -loglevel error \
    -f avfoundation -capture_cursor 1 -framerate 30 -i "$screen_device:none" \
    -t "$launch_seconds" -pix_fmt yuv420p -movflags +faststart \
    "$video_path" </dev/null >"$state_root/ffmpeg.log" 2>&1 &
  recorder_pid=$!
  sleep 2
  if ! kill -0 "$recorder_pid" 2>/dev/null; then
    log "warn: ffmpeg exited immediately; see $state_root/ffmpeg.log"
    recorder_pid=""
    record=0
  fi
else
  log "Screen recording disabled."
fi

# 5) Launch the app with an isolated HOME and content-ready signal.
log "Launching $app_name with isolated HOME"
rm -f "$benchmark_output"
open -n -g \
  --env "HOME=$test_home" \
  --env "GUI_FOR_CLI_APP_SUPPORT_NAME=$app_support_name" \
  --env "GFC_BENCHMARK_STARTUP=1" \
  --env "GFC_BENCHMARK_OUTPUT=$benchmark_output" \
  "$installed_app"

deadline=$((SECONDS + 60))
while [ "$SECONDS" -lt "$deadline" ]; do
  [ -s "$benchmark_output" ] && break
  sleep 1
done
[ -s "$benchmark_output" ] || fail "App did not report content readiness in 60s."
[ -d "$app_support_dir/BundleWorkspaces" ] || fail "App did not create BundleWorkspaces under app support."

# 6) Drive a quick page tour via AppleScript for the demo recording.
osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application id "$app_bundle_id" to activate
delay 2
tell application "System Events"
  tell process "$app_name"
    keystroke "1" using {command down}
    delay 1
    keystroke "2" using {command down}
    delay 1
    keystroke "3" using {command down}
    delay 1
  end tell
end tell
APPLESCRIPT

# 7) Run BAM/VCF actions end-to-end through the bundle test runner against a
#    fresh workspace, with the stub CLI on PATH via WGSEXTRACT_ALLOW_PATH_FALLBACK.
log "Running BAM/VCF actions via bundle test runner"
rm -rf "$workspace_dir"
WGSEXTRACT_ALLOW_PATH_FALLBACK=1 \
PATH="$stub_bin_dir:$PATH" \
  swift run --package-path "$repo_root/platform/apple" gui-for-cli bundle test \
    --workspace "$workspace_dir" \
    --report "$report_path" \
    --log "$log_path" \
    --input "bam_path=$fixtures_dir/sample.bam" \
    --action basic-info \
    --action detailed-info \
    --action coverage-sample \
    --action vcf-snp \
    "$repo_root/examples/WGSExtract"

passed_count="$(python3 -c "import json; print(json.load(open('$report_path'))['summary']['passed'])")"
failed_count="$(python3 -c "import json; print(json.load(open('$report_path'))['summary']['failed'])")"
log "Bundle test summary: passed=$passed_count failed=$failed_count"
[ "$failed_count" = "0" ] || fail "Bundle test reported $failed_count failed action(s); see $log_path"
[ "$passed_count" = "4" ] || fail "Expected 4 passed actions, got $passed_count"

# 8) Stop recording, quit the app, uninstall app + app data.
stop_recorder
log "Quitting app"
quit_app

log "Uninstalling app and app data"
rm -rf "$installed_app" "$app_support_dir"
[ ! -e "$installed_app" ] || fail "App still exists after uninstall: $installed_app"
[ ! -e "$app_support_dir" ] || fail "App data still exists after uninstall: $app_support_dir"

log "Action e2e passed for $app_name ($app_bundle_id)."
if [ -f "$video_path" ]; then
  log "Demo video: $video_path"
fi
log "Report:     $report_path"
log "Log:        $log_path"
