#!/bin/bash
# Builds the disk image that gets attached to a GitHub release.
#
#   ./scripts/make-dmg.sh dist/Snapper.app 0.1.0
#
# A DMG rather than a bare zip because it is the only format that can show a drag-to-Applications
# window, and because Gatekeeper's quarantine handling of a downloaded DMG is the path most people
# have muscle memory for. It is signed here so it can be notarized in its own right — a notarized
# app inside an unsigned DMG still makes Gatekeeper complain about the DMG.
set -euo pipefail

APP="${1:-dist/Snapper.app}"
VERSION="${2:-}"
IDENTITY="${CODESIGN_IDENTITY:-}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ -d "$APP" ] || die "No app bundle at $APP — run 'make app' first."

NAME="$(basename "$APP" .app)"
if [ -z "$VERSION" ]; then
  VERSION="$(defaults read "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")"
fi
OUT="$(dirname "$APP")/$NAME-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

bold "==> staging"
/usr/bin/ditto "$APP" "$STAGE/$NAME.app"
# The symlink is what makes "drag this onto that" possible inside the mounted image.
ln -s /Applications "$STAGE/Applications"

bold "==> creating $OUT"
rm -f "$OUT"
# UDZO is the compressed read-only format; -quiet keeps the build output readable. The volume name
# is what appears in Finder's sidebar once mounted.
hdiutil create \
  -volname "$NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$OUT"

if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
  bold "==> signing the disk image"
  # A DMG carries no hardened runtime of its own — that flag belongs to the app inside it — but it
  # does need a timestamp to be notarizable.
  codesign --force --timestamp --sign "$IDENTITY" "$OUT"
  codesign --verify --verbose=1 "$OUT" 2>&1 | sed 's/^/  /'
else
  echo "  (unsigned — set CODESIGN_IDENTITY to sign it)"
fi

echo
printf '\033[32m%s\033[0m  (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
