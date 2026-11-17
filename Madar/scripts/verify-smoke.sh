#!/bin/bash
# Smoke-test the real app: Debug build, install on an approved simulator, launch on an isolated synthetic
# store (MADAR_UI_STORE_ID, never the owner's data), check it stays up with no new crash, save a screenshot.
# Usage: bash scripts/verify-smoke.sh [KEY=VALUE ...]   e.g. MADAR_UI_HABIT_FIXTURE=showcase
# SIMULATOR may be the iPhone (default) or the approved iPad; SKIP_BUILD=1 reuses the last Debug build.
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
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  xcodebuild -project Madar.xcodeproj -scheme Madar -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath DerivedData \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build > "$OUT/build-$STAMP.log" 2>&1 \
    || { echo "verify-smoke: BUILD FAILED, see $OUT/build-$STAMP.log" >&2; grep -m10 "error:" "$OUT/build-$STAMP.log" >&2 || true; exit 1; }
fi
xcrun simctl bootstatus "$SIM" -b > /dev/null
xcrun simctl install "$SIM" DerivedData/Build/Products/Debug-iphonesimulator/Madar.app
CRASHES=~/Library/Logs/DiagnosticReports
before=$(ls "$CRASHES" 2>/dev/null | grep -c "^Madar" || true)
xcrun simctl terminate "$SIM" "$BUNDLE" > /dev/null 2>&1 || true
export SIMCTL_CHILD_MADAR_UI_STORE_ID="verify-$STAMP"
for pair in "$@"; do export "SIMCTL_CHILD_${pair%%=*}=${pair#*=}"; done
pid=$(xcrun simctl launch "$SIM" "$BUNDLE" | awk '{print $NF}')
sleep "${SMOKE_WAIT:-8}"
alive=$(xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -c "$BUNDLE" || true)
after=$(ls "$CRASHES" 2>/dev/null | grep -c "^Madar" || true)
SHOT="$OUT/smoke-$STAMP.png"
xcrun simctl io "$SIM" screenshot "$SHOT" > /dev/null 2>&1 || true
if [ "$alive" = "0" ] || [ "$after" -gt "$before" ]; then
  echo "verify-smoke: FAILED — app not running or a new crash report appeared (pid $pid). Screenshot: $SHOT" >&2
  ls -t "$CRASHES" 2>/dev/null | grep "^Madar" | head -1 >&2 || true
  exit 1
fi
echo "verify-smoke: PASSED — app running on an isolated store (verify-$STAMP). Screenshot: $SHOT"
