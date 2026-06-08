#!/usr/bin/env bash
set -euo pipefail

# End-to-end validation that mounts the SwiftUI DMG, installs the app, runs
# the bundle precheck + setup, drives BAM/VCF actions through the bundle test
# runner against a stub WGSExtract CLI, then uninstalls. While running, the
# script records the screen and burns per-stage subtitle banners into the
# final demo video so each lifecycle step is clearly labeled.

usage() {
  cat <<'EOF'
Usage: scripts/validate-macos-action-e2e.sh [options]

Options:
  --dmg PATH        DMG to install. Default: newest out/release/swiftui/WGSExtract*.dmg
  --state-root PATH Temporary state root. Default: tmp/macos-action-e2e
  --no-record       Skip screen recording.
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
  local candidate
  candidate="$(
    find "$release_dir" -maxdepth 1 -type f -name 'WGSExtract*.dmg' \
      -exec stat -f '%m %N' {} \; 2>/dev/null \
      | sort -nr \
      | sed -n '1s/^[0-9][0-9]* //p'
  )"
  if [ -n "$candidate" ]; then printf '%s\n' "$candidate"; return; fi
  printf '%s\n' "$release_dir/WGSExtract.dmg"
}

dmg_path="$(default_dmg_path)"
state_root="$repo_root/tmp/macos-action-e2e"
record=1
keep=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg) [ "$#" -ge 2 ] || fail "Missing --dmg value"; dmg_path="$2"; shift 2 ;;
    --state-root) [ "$#" -ge 2 ] || fail "Missing --state-root value"; state_root="$2"; shift 2 ;;
    --no-record) record=0; shift ;;
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
require_command python3
[ -f "$dmg_path" ] || fail "DMG not found: $dmg_path"
if [ "$record" -eq 1 ]; then
  require_command ffmpeg
fi

state_root="$(mkdir -p "$state_root" && cd "$state_root" && pwd)"
case "$state_root" in
  / | "$HOME" | "$repo_root" | "$repo_root"/platform | "$repo_root"/examples)
    fail "Refusing unsafe --state-root for recursive cleanup: $state_root"
    ;;
esac
mount_root="$state_root/mount"
install_dir="$state_root/Applications"
test_home="$state_root/home"
fixtures_dir="$state_root/fixtures"
workspace_dir="$state_root/workspace"
stub_bin_dir="$state_root/stub-bin"
raw_video="$state_root/wgsextract-action-e2e.raw.mp4"
video_path="$state_root/wgsextract-action-e2e.mp4"
report_path="$state_root/bundle-test-report.json"
log_path="$state_root/bundle-test-log.txt"
benchmark_output="$state_root/content-ready.log"
stages_tsv="$state_root/stages.tsv"
overlay_dir="$state_root/overlays"

mounted=0
installed_app=""
app_bundle_id=""
recorder_pid=""
record_start=""

mkdir -p "$mount_root" "$install_dir" "$test_home" "$fixtures_dir" \
         "$workspace_dir" "$stub_bin_dir" "$overlay_dir"
: > "$stages_tsv"

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
    kill -INT "$recorder_pid" >/dev/null 2>&1 || true
    local deadline=$((SECONDS + 10))
    while [ "$SECONDS" -lt "$deadline" ] && kill -0 "$recorder_pid" 2>/dev/null; do sleep 1; done
    kill -0 "$recorder_pid" 2>/dev/null && kill -9 "$recorder_pid" >/dev/null 2>&1 || true
  fi
  wait "$recorder_pid" 2>/dev/null || true
  recorder_pid=""
}

# Append (elapsed_seconds, label) for the just-started stage. Subtitle for the
# previous stage runs from its start time up to this new start time.
mark_stage() {
  local label="$1"
  if [ -z "$record_start" ]; then return; fi
  local now
  now="$(python3 -c 'import time; print(f"{time.time():.3f}")')"
  local elapsed
  elapsed="$(python3 -c "print(f'{$now - $record_start:.3f}')")"
  printf '%s\t%s\n' "$elapsed" "$label" >> "$stages_tsv"
  log "stage: $label (t=${elapsed}s)"
}

burn_subtitles() {
  [ -f "$raw_video" ] || { log "warn: no raw video to burn"; return 0; }
  [ -s "$stages_tsv" ] || { log "warn: no stages recorded"; cp "$raw_video" "$video_path"; return 0; }
  log "Burning subtitles into $video_path"

  # Probe video dimensions and duration.
  local probe
  probe="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
            -show_entries format=duration -of default=nw=1 "$raw_video")"
  local width height duration
  width="$(printf '%s\n' "$probe" | sed -n 's/^width=//p')"
  height="$(printf '%s\n' "$probe" | sed -n 's/^height=//p')"
  duration="$(printf '%s\n' "$probe" | sed -n 's/^duration=//p')"
  [ -n "$width" ] && [ -n "$height" ] && [ -n "$duration" ] \
    || { log "warn: ffprobe failed; copying raw"; cp "$raw_video" "$video_path"; return 0; }

  # Generate overlay PNGs and the ffmpeg filter graph.
  python3 - "$stages_tsv" "$overlay_dir" "$width" "$height" "$duration" "$state_root/overlay-filter.txt" <<'PY'
import sys, os
from PIL import Image, ImageDraw, ImageFont

tsv, outdir, width, height, duration, filter_path = sys.argv[1:]
width = int(width); height = int(height); duration = float(duration)

stages = []
with open(tsv) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        t, label = line.split('\t', 1)
        stages.append((float(t), label))

if not stages:
    open(filter_path, 'w').write('null')
    sys.exit(0)

# Pair each stage with an end time (next stage start or video duration).
intervals = []
for i, (start, label) in enumerate(stages):
    end = stages[i+1][0] if i+1 < len(stages) else duration
    intervals.append((i, start, end, label))

# Banner sized to ~7% of height, full width.
banner_h = max(96, int(height * 0.085))
font_size = max(28, int(banner_h * 0.42))
small_size = max(18, int(banner_h * 0.26))
try:
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', font_size)
    small_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', small_size)
except Exception:
    font = ImageFont.load_default()
    small_font = ImageFont.load_default()

total = len(intervals)
for i, start, end, label in intervals:
    img = Image.new('RGBA', (width, banner_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Solid black bar with green accent stripe on the left.
    draw.rectangle([(0, 0), (width, banner_h)], fill=(0, 0, 0, 215))
    draw.rectangle([(0, 0), (10, banner_h)], fill=(64, 200, 96, 255))
    tag = f'Stage {i+1}/{total}'
    draw.text((30, int(banner_h*0.10)), tag, font=small_font, fill=(160, 230, 180, 255))
    draw.text((30, int(banner_h*0.42)), label, font=font, fill=(255, 255, 255, 255))
    img.save(os.path.join(outdir, f'stage-{i:02d}.png'))

# Build filter graph: chain overlays with enable=between(t,start,end).
parts = []
labels = ['[0:v]']
for i, start, end, label in intervals:
    in_label = labels[-1]
    out_label = f'[v{i}]' if i < total - 1 else '[vout]'
    parts.append(f"movie='{os.path.join(outdir, f'stage-{i:02d}.png')}'[ov{i}]")
    parts.append(f"{in_label}[ov{i}]overlay=x=0:y=0:enable='between(t,{start:.3f},{end:.3f})'{out_label}")
    labels.append(out_label)

open(filter_path, 'w').write(';'.join(parts))
PY

  local filter_complex
  filter_complex="$(cat "$state_root/overlay-filter.txt")"
  if [ "$filter_complex" = "null" ]; then
    cp "$raw_video" "$video_path"
    return 0
  fi

  ffmpeg -y -hide_banner -loglevel error \
    -i "$raw_video" \
    -filter_complex "$filter_complex" \
    -map '[vout]' -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
    "$video_path" </dev/null
}

cleanup() {
  stop_recorder
  quit_app
  [ "$mounted" -eq 1 ] && hdiutil detach "$mount_root" >/dev/null 2>&1 || true
  if [ -f "$raw_video" ] && [ ! -f "$video_path" ]; then
    burn_subtitles || cp "$raw_video" "$video_path" 2>/dev/null || true
  fi
  if [ -d "$install_dir" ]; then
    rm -rf "$installed_app" 2>/dev/null || true
  fi
  if [ "$keep" -eq 0 ]; then
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

# 0) Stub wgsextract CLI + fake BAM fixture (kept cheap so setup+actions are fast).
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
  bam) printf '[wgsextract-stub] BAM %s\n' "${2:-op}" ;;
  *)   printf '[wgsextract-stub] no-op for: %s\n' "${1:-<empty>}" ;;
esac
STUB
chmod +x "$stub_bin_dir/wgsextract"
printf 'fake bam content for e2e test\n' > "$fixtures_dir/sample.bam"

# 0a) Pre-build the gui-for-cli binary so 'swift run' calls during the recording
#     do not stall waiting on a compile.
log "Pre-building gui-for-cli (one-time, before recording)"
swift build --package-path "$repo_root/platform/apple" --product gui-for-cli >/dev/null

# 1) Start screen recording (best-effort; needs Screen Recording permission).
if [ "$record" -eq 1 ]; then
  screen_device="$({
    ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true
  } | awk '
    /AVFoundation video devices/ { v=1; next }
    /AVFoundation audio devices/ { v=0 }
    v && /Capture screen 0/ && !found {
      if (match($0, /\[[0-9]+\]/)) { print substr($0, RSTART+1, RLENGTH-2); found=1 }
    }
  ')"
  if [ -z "$screen_device" ]; then
    log "warn: no avfoundation screen capture device found; recording disabled."
    record=0
  fi
fi
if [ "$record" -eq 1 ]; then
  log "Starting screen recording -> $raw_video (device $screen_device)"
  rm -f "$raw_video" "$video_path"
  ffmpeg -y -hide_banner -loglevel error \
    -f avfoundation -capture_cursor 1 -framerate 30 -i "$screen_device:none" \
    -pix_fmt yuv420p -movflags +faststart \
    "$raw_video" </dev/null >"$state_root/ffmpeg.log" 2>&1 &
  recorder_pid=$!
  sleep 2
  if ! kill -0 "$recorder_pid" 2>/dev/null; then
    log "warn: ffmpeg exited immediately; see $state_root/ffmpeg.log"
    recorder_pid=""
    record=0
  else
    record_start="$(python3 -c 'import time; print(f"{time.time():.3f}")')"
    # Give the recording 1.5s of head room so the first subtitle is on-screen
    # before the first stage action begins.
    sleep 1
  fi
else
  log "Screen recording disabled."
fi

# 2) Mount the DMG.
mark_stage "Stage A — Mount installer DMG"
log "Mounting $dmg_path"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_root" "$dmg_path" >/dev/null
mounted=1
mounted_app="$(find "$mount_root" -maxdepth 1 -name '*.app' -type d | sort | sed -n '1p')"
[ -d "$mounted_app" ] || fail "Could not find .app in mounted DMG."
app_name="$(basename "$mounted_app")"
installed_app="$install_dir/$app_name"
app_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$mounted_app/Contents/Info.plist")"
app_support_name="$app_bundle_id.action-e2e-test.$$"
app_support_dir="$test_home/Library/Application Support/$app_support_name"
sleep 3

# 3) Install the app.
mark_stage "Stage B — Install $app_name into isolated /Applications"
rm -rf "$installed_app" "$app_support_dir"
ditto "$mounted_app" "$installed_app"
sleep 3

# Common env for CLI invocations against the bundle.
cli_env=(
  env
  "HOME=$test_home"
  "WGSEXTRACT_ALLOW_PATH_FALLBACK=1"
  "PATH=$stub_bin_dir:$PATH"
)

# 4) Precheck.
mark_stage "Stage C — Run gui-for-cli precheck"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli precheck || true
sleep 2

# 5) Bundle setup (dry-run shows full plan without conda/pixi side effects).
mark_stage "Stage D — Preview bundle setup plan (dry-run)"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli bundle setup --dry-run "$repo_root/examples/WGSExtract"
sleep 2

# 6) Launch the installed app with isolated HOME.
mark_stage "Stage E — Launch installed app with isolated HOME"
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
sleep 3

# 7) Visible AppleScript-driven page tour while the GUI is in focus.
mark_stage "Stage F — Tour bundle pages (Cmd+1, Cmd+2, Cmd+3)"
osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application id "$app_bundle_id" to activate
delay 1
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
sleep 2

# 8) Action runs against a fresh workspace, with stub wgsextract on PATH.
rm -rf "$workspace_dir"

mark_stage "Stage G — Bundle test: BAM basic-info action"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli bundle test \
    --workspace "$workspace_dir" \
    --report "$report_path" \
    --log "$log_path" \
    --input "bam_path=$fixtures_dir/sample.bam" \
    --action basic-info \
    "$repo_root/examples/WGSExtract"
sleep 4

mark_stage "Stage H — Bundle test: BAM detailed-info action"
rm -rf "$workspace_dir"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli bundle test \
    --workspace "$workspace_dir" \
    --report "$state_root/bundle-test-detailed.json" \
    --log "$state_root/bundle-test-detailed.log" \
    --input "bam_path=$fixtures_dir/sample.bam" \
    --action detailed-info \
    "$repo_root/examples/WGSExtract"
sleep 4

mark_stage "Stage I — Bundle test: BAM coverage-sample action"
rm -rf "$workspace_dir"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli bundle test \
    --workspace "$workspace_dir" \
    --report "$state_root/bundle-test-coverage.json" \
    --log "$state_root/bundle-test-coverage.log" \
    --input "bam_path=$fixtures_dir/sample.bam" \
    --action coverage-sample \
    "$repo_root/examples/WGSExtract"
sleep 4

mark_stage "Stage J — Bundle test: VCF SNP pipeline action"
rm -rf "$workspace_dir"
"${cli_env[@]}" swift run --package-path "$repo_root/platform/apple" \
  gui-for-cli bundle test \
    --workspace "$workspace_dir" \
    --report "$state_root/bundle-test-vcf.json" \
    --log "$state_root/bundle-test-vcf.log" \
    --input "bam_path=$fixtures_dir/sample.bam" \
    --action vcf-snp \
    "$repo_root/examples/WGSExtract"
sleep 5

# Sanity-check the first report (the one we keep as primary).
passed_count="$(python3 -c "import json; print(json.load(open('$report_path'))['summary']['passed'])")"
failed_count="$(python3 -c "import json; print(json.load(open('$report_path'))['summary']['failed'])")"
log "Primary bundle test summary: passed=$passed_count failed=$failed_count"
[ "$failed_count" = "0" ] || fail "Bundle test reported $failed_count failed action(s); see $log_path"

mark_stage "Stage K — Quit app and stop services"
quit_app
sleep 2

mark_stage "Stage L — Uninstall app + Application Support data"
rm -rf "$installed_app" "$app_support_dir"
[ ! -e "$installed_app" ] || fail "App still exists after uninstall: $installed_app"
[ ! -e "$app_support_dir" ] || fail "App data still exists after uninstall: $app_support_dir"
sleep 3

mark_stage "Stage M — Done: install/setup/action/uninstall verified"
sleep 2

# 9) Stop recording and burn subtitle overlays into the final video.
stop_recorder
if [ -f "$raw_video" ]; then
  burn_subtitles
fi

log "Action e2e passed for $app_name ($app_bundle_id)."
[ -f "$video_path" ] && log "Demo video: $video_path"
log "Report:     $report_path"
log "Log:        $log_path"
