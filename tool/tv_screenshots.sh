#!/usr/bin/env bash
#
# Capture Android TV screenshots for the Play Store listing.
#
# Creates/boots an Android TV emulator (tv_1080p -> 1920x1080, 16:9), runs the
# Flutter integration_test screenshot driver, and collects PNGs into ./screenshots/.
# Pass --sync-metadata to also copy them into the fastlane TV screenshots folder.
#
#   ./tool/tv_screenshots.sh                 # capture into ./screenshots/
#   ./tool/tv_screenshots.sh --sync-metadata # capture + copy into store metadata
#
# Env overrides: ANDROID_SDK_ROOT / ANDROID_HOME, TV_API (default 34),
#                TV_AVD (default arc_tv_avd), TV_EMU_FLAGS, KEEP_EMULATOR=1.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ANDROID_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
API="${TV_API:-34}"
AVD_NAME="${TV_AVD:-arc_tv_avd}"
OUT_DIR="$ROOT/screenshots"
META_DIR="$ROOT/fastlane/metadata/android/en-US/images/tvScreenshots"

SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager"
EMULATOR="$ANDROID_SDK/emulator/emulator"
ADB="$ANDROID_SDK/platform-tools/adb"

for bin in "$SDKMANAGER" "$AVDMANAGER" "$EMULATOR" "$ADB"; do
  [ -x "$bin" ] || { echo "ERROR: not found/executable: $bin (set ANDROID_SDK_ROOT)"; exit 1; }
done

# Android TV system images are published for x86 and arm64-v8a (no x86_64).
case "$(uname -m)" in
  arm64|aarch64) ABI="arm64-v8a" ;;
  *)             ABI="x86" ;;
esac
SYSIMG="system-images;android-${API};android-tv;${ABI}"

echo "==> SDK:          $ANDROID_SDK"
echo "==> System image: $SYSIMG"
echo "==> AVD:          $AVD_NAME"

# 1. Install required SDK packages (idempotent; auto-accept licenses).
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" "platform-tools" "emulator" "platforms;android-${API}" "$SYSIMG"

# 2. Create the TV AVD if it does not already exist.
if ! "$AVDMANAGER" list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}\b"; then
  echo "==> Creating AVD $AVD_NAME ..."
  echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSIMG" --device "tv_1080p" --force
fi

# 3. Boot the emulator and wait for it to come up.
echo "==> Booting emulator ..."
# shellcheck disable=SC2086
"$EMULATOR" -avd "$AVD_NAME" -no-snapshot -no-boot-anim -no-audio \
  -gpu swiftshader_indirect ${TV_EMU_FLAGS:-} >/tmp/arc_tv_emulator.log 2>&1 &
EMU_PID=$!
cleanup() { [ "${KEEP_EMULATOR:-0}" = "1" ] || kill "$EMU_PID" 2>/dev/null || true; }
trap cleanup EXIT

"$ADB" wait-for-device
echo "==> Waiting for boot to complete ..."
until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 2
done
"$ADB" shell input keyevent 82 >/dev/null 2>&1 || true # dismiss keyguard
echo "==> Emulator booted."

DEVICE_ID="$("$ADB" devices | awk '/emulator-/{print $1; exit}')"
[ -n "$DEVICE_ID" ] || { echo "ERROR: no emulator device found"; exit 1; }
echo "==> Device: $DEVICE_ID"

# 4. Run the Flutter integration_test screenshot driver.
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d "$DEVICE_ID"

echo "==> Screenshots written to: $OUT_DIR"
ls -1 "$OUT_DIR" 2>/dev/null || true

# 5. Optionally sync into the fastlane TV screenshots metadata folder.
#    NOTE: Play requires 24-bit PNG / JPEG with NO alpha for TV screenshots.
#    Captures are usually opaque; if Play rejects one, flatten it (e.g.
#    `sips -s format jpeg`) before re-uploading.
if [ "${1:-}" = "--sync-metadata" ]; then
  mkdir -p "$META_DIR"
  i=1
  for f in "$OUT_DIR"/*.png; do
    [ -e "$f" ] || continue
    cp "$f" "$META_DIR/screenshot_${i}.png"
    i=$((i + 1))
  done
  echo "==> Synced $((i - 1)) screenshot(s) into $META_DIR"
fi
