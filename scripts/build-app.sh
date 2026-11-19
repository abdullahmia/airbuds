#!/bin/bash
# Builds "AirBuds.app" into build/. Needs only the Xcode Command Line Tools.
#
#   scripts/build-app.sh              release build for this Mac's chip
#   scripts/build-app.sh --universal  arm64 + x86_64
#   scripts/build-app.sh --install    also copy to /Applications
#   VERSION=1.2.0 scripts/build-app.sh  stamp a version into Info.plist (CI sets this from the tag)
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install) INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$UNIVERSAL" = 1 ]; then
  swift build -c release --product AirBuds --arch arm64 --arch x86_64
  BIN="$(swift build -c release --product AirBuds --arch arm64 --arch x86_64 --show-bin-path)/AirBuds"
else
  swift build -c release --product AirBuds
  BIN="$(swift build -c release --product AirBuds --show-bin-path)/AirBuds"
fi

APP="build/AirBuds.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AirBuds"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough for Bluetooth permission and Open at Login on this Mac.
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
  pkill -x AirBuds 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/AirBuds.app"
  ditto "$APP" "/Applications/AirBuds.app"
  echo "Installed to /Applications/AirBuds.app"
fi
