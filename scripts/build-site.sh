#!/bin/bash
# Builds the landing page (site/index.html) for GitHub Pages: fills in the latest
# release (version, DMG link and size, date) and copies the icon and screenshots
# (site/icon.png and site/screenshots link to them in docs/). The Pages workflow
# runs this after every release.
#
#   scripts/build-site.sh            build into _site/
#   scripts/build-site.sh out        build into out/
#   python3 -m http.server -d _site  preview at http://localhost:8000
#
# Needs the GitHub CLI: logged in locally, GH_TOKEN in CI.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-_site}"
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
OWNER="$(echo "${REPO%%/*}" | tr '[:upper:]' '[:lower:]')"
SITE_URL="https://$OWNER.github.io/${REPO#*/}/"
REPO_URL="https://github.com/$REPO"

# tag, release page, date, DMG link, DMG bytes (tab-separated)
RELEASE="$(gh api "repos/$REPO/releases/latest" --jq '[
  .tag_name,
  .html_url,
  (.published_at | fromdateiso8601 | strftime("%b %d, %Y")),
  (.assets[] | select(.name | endswith(".dmg")) | .browser_download_url, (.size | tostring))
] | @tsv')"
IFS=$'\t' read -r TAG RELEASE_URL RELEASE_DATE DMG_URL DMG_BYTES <<< "$RELEASE"
if [ -z "${DMG_URL:-}" ]; then
  echo "The latest release ($TAG) has no .dmg asset" >&2
  exit 1
fi
VERSION="${TAG#v}"
RELEASE_DATE="${RELEASE_DATE/ 0/ }"   # "Nov 05, 2026" -> "Nov 5, 2026"
DMG_SIZE="$(awk -v b="$DMG_BYTES" 'BEGIN { printf "%.1f MB", b / 1000000 }')"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -RL site/. "$OUT/"   # -L: copy the files the docs/ links point at
sed -e "s|{{VERSION}}|$VERSION|g" \
    -e "s|{{DMG_URL}}|$DMG_URL|g" \
    -e "s|{{DMG_SIZE}}|$DMG_SIZE|g" \
    -e "s|{{RELEASE_URL}}|$RELEASE_URL|g" \
    -e "s|{{RELEASE_DATE}}|$RELEASE_DATE|g" \
    -e "s|{{REPO_URL}}|$REPO_URL|g" \
    -e "s|{{SITE_URL}}|$SITE_URL|g" \
    site/index.html > "$OUT/index.html"
if grep -o '{{[A-Z_]*}}' "$OUT/index.html"; then
  echo "Unfilled placeholders in $OUT/index.html (above)" >&2
  exit 1
fi

echo "Built $OUT for AirBuds $VERSION ($DMG_SIZE, $RELEASE_DATE)"
