#!/bin/bash
# Builds the installer package that gets attached to a GitHub release.
#
#   ./scripts/make-pkg.sh dist/Snapper.app 0.1.0
#
# A .pkg rather than a .dmg: double-click and it is installed, with no drag-and-drop step and no
# chance of someone running the app from the mounted image and wondering why it vanishes.
#
# Signing a package needs a "Developer ID Installer" certificate, which is a *different* certificate
# from the "Developer ID Application" one that signs the app itself. Both come from the same Apple
# account; ./scripts/setup-developer-id.sh installer sets the second one up.
set -euo pipefail

APP="${1:-dist/Snapper.app}"
VERSION="${2:-}"
IDENTIFIER="com.zikopoulos.snapper"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ -d "$APP" ] || die "No app bundle at $APP — run 'make app' first."

NAME="$(basename "$APP" .app)"
if [ -z "$VERSION" ]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
fi
OUT="$(dirname "$APP")/$NAME-$VERSION.pkg"

MIN_OS="$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist" 2>/dev/null || echo "26.0")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$NAME" 2>/dev/null | tr ' ' ',' || echo "arm64")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/root"
mkdir -p "$STAGE"

bold "==> staging"
# A clean root containing nothing but the app, so the package cannot pick up strays.
/usr/bin/ditto "$APP" "$STAGE/$NAME.app"

bold "==> component properties"
pkgbuild --analyze --root "$STAGE" "$WORK/component.plist" >/dev/null
# BundleIsRelocatable defaults to true, which means the installer hunts for an existing copy of the
# app *anywhere* on the disk and updates that instead of installing to /Applications. Someone with a
# build in ~/Applications would have it silently overwritten and nothing would appear where they
# expected. Pinning it to false is the single most important line in this script.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"
/usr/libexec/PlistBuddy -c "Print :0:BundleIsRelocatable" "$WORK/component.plist" | sed 's/^/  BundleIsRelocatable: /'

bold "==> building component package"
pkgbuild \
  --root "$STAGE" \
  --component-plist "$WORK/component.plist" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location /Applications \
  "$WORK/component.pkg" >/dev/null
echo "  $(du -h "$WORK/component.pkg" | cut -f1)"

bold "==> distribution"
# Synthesise, then add the checks Installer can enforce before it starts writing: the OS floor from
# the bundle, and the architectures the binary actually contains. Without these, an Intel Mac or an
# older macOS installs it happily and the app simply never launches.
productbuild --synthesize --package "$WORK/component.pkg" "$WORK/distribution.xml" >/dev/null 2>&1

python3 - "$WORK/distribution.xml" "$NAME" "$VERSION" "$MIN_OS" "$ARCHS" <<'PY'
import sys, xml.etree.ElementTree as ET
path, name, version, min_os, archs = sys.argv[1:6]
tree = ET.parse(path); root = tree.getroot()

def replace(tag, node):
    for existing in root.findall(tag):
        root.remove(existing)
    root.append(node)

title = ET.Element("title"); title.text = f"{name} {version}"
replace("title", title)

options = ET.Element("options", {"customize": "never", "require-scripts": "false",
                                 "hostArchitectures": archs})
replace("options", options)

vc = ET.Element("volume-check")
allowed = ET.SubElement(vc, "allowed-os-versions")
ET.SubElement(allowed, "os-version", {"min": min_os})
replace("volume-check", vc)

tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"  title: {name} {version}")
print(f"  requires: macOS {min_os} or later, {archs}")
PY

bold "==> assembling"
rm -f "$OUT"
if [ -n "$INSTALLER_IDENTITY" ]; then
  echo "  signing with '$INSTALLER_IDENTITY'"
  productbuild \
    --distribution "$WORK/distribution.xml" \
    --package-path "$WORK" \
    --sign "$INSTALLER_IDENTITY" \
    --timestamp \
    "$OUT" >/dev/null
else
  printf '  \033[33munsigned\033[0m — set INSTALLER_IDENTITY to sign it\n'
  echo "  an unsigned package cannot be notarized, and Gatekeeper will refuse it"
  productbuild \
    --distribution "$WORK/distribution.xml" \
    --package-path "$WORK" \
    "$OUT" >/dev/null
fi

bold "==> verifying"
pkgutil --check-signature "$OUT" 2>&1 | sed 's/^/  /' || true
# Proves the payload lands where intended, without installing anything.
echo "  payload:"
pkgutil --payload-files "$OUT" 2>/dev/null | head -4 | sed 's/^/    /'
echo "    ... $(pkgutil --payload-files "$OUT" 2>/dev/null | wc -l | tr -d ' ') entries"

echo
printf '\033[32m%s\033[0m  (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
