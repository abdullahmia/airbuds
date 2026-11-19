#!/bin/bash
# Writes dist/appcast.xml, the Sparkle update feed for one release: it points
# at that release's zip and carries the zip's EdDSA signature. Installed copies
# read it from the latest release (SUFeedURL in Info.plist). Run after make-dmg.sh.
#
#   scripts/make-appcast.sh 1.2.0 42                              key from your login keychain
#   SPARKLE_PRIVATE_KEY="$KEY" scripts/make-appcast.sh 1.2.0 42   key from the environment (CI)
#
# The second argument is the build number (CFBundleVersion) Sparkle compares.
# REPO (default abdullahmia/airbuds) or DOWNLOAD_URL change where the zip lives.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/make-appcast.sh <version> <build number>}"
BUILD="${2:?usage: scripts/make-appcast.sh <version> <build number>}"
ZIP="dist/AirBuds-$VERSION.zip"
[ -f "$ZIP" ] || { echo "missing $ZIP: run scripts/make-dmg.sh first" >&2; exit 1; }

REPO="${REPO:-abdullahmia/airbuds}"
URL="${DOWNLOAD_URL:-https://github.com/$REPO/releases/download/v$VERSION/AirBuds-$VERSION.zip}"
NOTES="https://github.com/$REPO/releases/tag/v$VERSION"

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN_UPDATE" ] || swift package resolve >/dev/null
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")"
else
  SIGNATURE="$("$SIGN_UPDATE" -p "$ZIP")"
fi
LENGTH="$(stat -f %z "$ZIP")"
DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)"

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AirBuds</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>AirBuds $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$NOTES</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<p>AirBuds $VERSION is available. <a href="$NOTES">See what's new</a>.</p>]]></description>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote dist/appcast.xml for $VERSION (build $BUILD)"
