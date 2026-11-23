#!/bin/bash
# Smoke-test the real app: Debug build, install on an approved simulator, launch on an isolated synthetic
# store, wait for its first ready screen, check for a crash, and save a screenshot.
# Usage: bash scripts/verify-smoke.sh [KEY=VALUE ...]   e.g. MADAR_UI_HABIT_FIXTURE=showcase
# SIMULATOR may be the iPhone (default) or the approved iPad; SKIP_BUILD=1 reuses the last Debug build.
# SMOKE_TIMEOUT sets the maximum number of seconds to wait for a ready screen (default 45).
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${SIMULATOR:-390840AD-4FF0-476F-8E1D-E0C521A58E45}"
case "$SIM" in
  390840AD-4FF0-476F-8E1D-E0C521A58E45|85FA4D17-2DBF-46D6-837E-9221597B89DD) ;;
  *) echo "verify-smoke: only the two approved simulators are allowed" >&2; exit 2 ;;
esac
BUNDLE=com.alqzan.madar2
OUT=Artifacts/verify; mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S)
READY_TIMEOUT=${SMOKE_TIMEOUT-${SMOKE_WAIT-45}}
if [[ ! "$READY_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "verify-smoke: SMOKE_TIMEOUT must be a positive integer" >&2
  exit 2
fi
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  xcodebuild -project Madar.xcodeproj -scheme Madar -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath DerivedData \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build > "$OUT/build-$STAMP.log" 2>&1 \
    || { echo "verify-smoke: BUILD FAILED, see $OUT/build-$STAMP.log" >&2; grep -m10 "error:" "$OUT/build-$STAMP.log" >&2 || true; exit 1; }
fi
xcrun simctl bootstatus "$SIM" -b > /dev/null
xcrun simctl install "$SIM" DerivedData/Build/Products/Debug-iphonesimulator/Madar.app
APP_DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
TOKEN=$(/usr/bin/uuidgen)
MARKER="$APP_DATA/tmp/madar-smoke-ready-$TOKEN"
(set -C; : > "$MARKER")
trap 'rm -f -- "$MARKER"' EXIT
CRASHES=~/Library/Logs/DiagnosticReports
before=$(ls "$CRASHES" 2>/dev/null | grep -c "^Madar" || true)
xcrun simctl terminate "$SIM" "$BUNDLE" > /dev/null 2>&1 || true
for pair in "$@"; do export "SIMCTL_CHILD_${pair%%=*}=${pair#*=}"; done
export SIMCTL_CHILD_MADAR_UI_STORE_ID="$TOKEN"
export SIMCTL_CHILD_MADAR_SMOKE_READY_TOKEN="$TOKEN"
SECONDS=0
pid=$(xcrun simctl launch "$SIM" "$BUNDLE" | awk '{print $NF}')
if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "verify-smoke: FAILED — Simulator did not return an app PID" >&2
  exit 1
fi
while [[ ! -s "$MARKER" && $SECONDS -lt $READY_TIMEOUT ]] && kill -0 "$pid" 2>/dev/null; do
  sleep 1
done
ready_after=$SECONDS
screen=$(cat "$MARKER" 2>/dev/null || true)
SHOT="$OUT/smoke-$STAMP.png"
screenshot_result="Screenshot: $SHOT"
screenshot_ok=true
if ! xcrun simctl io "$SIM" screenshot "$SHOT" > /dev/null 2>&1 || [[ ! -s "$SHOT" ]]; then
  screenshot_ok=false
  screenshot_result="Screenshot capture failed"
fi
after=$(ls "$CRASHES" 2>/dev/null | grep -c "^Madar" || true)
if ! kill -0 "$pid" 2>/dev/null || [ "$after" -gt "$before" ]; then
  echo "verify-smoke: FAILED — app not running or a new crash report appeared (pid $pid). $screenshot_result" >&2
  ls -t "$CRASHES" 2>/dev/null | grep "^Madar" | head -1 >&2 || true
  exit 1
fi
if [[ -z "$screen" ]]; then
  echo "verify-smoke: FAILED — no ready screen after ${ready_after}s (pid $pid). $screenshot_result" >&2
  exit 1
fi
if [[ "$screenshot_ok" == false ]]; then
  echo "verify-smoke: FAILED — $screen appeared in ${ready_after}s. $screenshot_result" >&2
  exit 1
fi
echo "verify-smoke: PASSED — $screen appeared in ${ready_after}s (isolated store $SIMCTL_CHILD_MADAR_UI_STORE_ID). $screenshot_result"
