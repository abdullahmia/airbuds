#!/bin/bash
# Packages build/AirBuds.app into a drag-to-Applications DMG and a zip,
# plus SHA256SUMS.txt, in dist/. Run scripts/build-app.sh first.
#
#   scripts/make-dmg.sh 1.2.0
#
# The DMG window (background art, icon positions, volume icon) is laid out by
# dmgbuild, which writes the window settings directly instead of scripting
# Finder, so it also works on CI. It's installed into .build/dmgbuild-venv on
# first run; needs Python 3.10 or later (set PYTHON to pick one).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/make-dmg.sh <version>}"
APP="build/AirBuds.app"
NAME="AirBuds-$VERSION"
[ -d "$APP" ] || { echo "missing $APP: run scripts/build-app.sh first" >&2; exit 1; }

DMGBUILD_PACKAGES=(dmgbuild==1.6.7 ds_store==1.3.3 mac_alias==2.2.3)
VENV=".build/dmgbuild-venv"
if ! "$VENV/bin/pip" freeze 2>/dev/null | grep -qx "${DMGBUILD_PACKAGES[0]}"; then
  PYTHON="${PYTHON:-python3}"
  "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || { echo "dmgbuild needs Python 3.10 or later; set PYTHON=/path/to/python3" >&2; exit 1; }
  rm -rf "$VENV"
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "${DMGBUILD_PACKAGES[@]}"
fi

rm -rf dist && mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

swift scripts/dmg-background.swift "$STAGE"
# hdiutil sometimes fails with "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3 4 5; do
  if "$VENV/bin/dmgbuild" -s scripts/dmg-settings.py \
      -D app="$APP" -D background="$STAGE/background.png" -D icon=Resources/AppIcon.icns \
      "AirBuds" "dist/$NAME.dmg" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" = 5 ] && { echo "dmgbuild failed" >&2; exit 1; }
  sleep $((attempt * 3))
done
ditto -c -k --keepParent "$APP" "dist/$NAME.zip"

(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
ls -lh dist
cat dist/SHA256SUMS.txt
