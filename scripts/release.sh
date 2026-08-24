#!/bin/bash
# Cuts a release: test, build, notarize, package, publish.
#
#   ./scripts/release.sh 0.2.0        (or: make release VERSION=0.2.0)
#
# Everything that can be checked locally is checked before anything irreversible happens, because
# the irreversible parts — a pushed tag, a published release — are annoying to undo. The one
# confirmation prompt is immediately before publishing.
#
# Order matters: the app is notarized and stapled *first*, then the package and zip are built from
# the stapled bundle. Done the other way round, the copy inside the installer would carry no ticket
# and would still need a network to pass Gatekeeper.
set -euo pipefail

VERSION="${1:-$(cat VERSION 2>/dev/null || true)}"
NAME="Snapper"
DIST="dist"
APP="$DIST/$NAME.app"
PROFILE="${SNAPPER_NOTARY_PROFILE:-snapper-notary}"

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ -n "$VERSION" ] || die "Usage: $0 <version>   e.g. $0 0.2.0"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] \
  || die "'$VERSION' is not a version. Use MAJOR.MINOR.PATCH, optionally with a -beta.1 suffix."

TAG="v$VERSION"
PKG="$DIST/$NAME-$VERSION.pkg"
ZIP="$DIST/$NAME-$VERSION.zip"
SUMS="$DIST/$NAME-$VERSION-checksums.txt"

# ---------------------------------------------------------------- preflight

bold "==> preflight"

command -v gh >/dev/null || die "The GitHub CLI is not installed. brew install gh"
gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"
ok "GitHub CLI authenticated"

git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."

if [ -n "$(git status --porcelain)" ]; then
  bad "the working tree has uncommitted changes"
  git status --short | sed 's/^/    /'
  die "Commit or stash them first — a release should be reproducible from its tag."
fi
ok "working tree clean"

git rev-parse "$TAG" >/dev/null 2>&1 && die "Tag $TAG already exists. Bump the version or delete the tag."
gh release view "$TAG" >/dev/null 2>&1 && die "Release $TAG already exists on GitHub."
ok "$TAG is unused"

FILE_VERSION="$(cat VERSION 2>/dev/null || true)"
if [ "$FILE_VERSION" != "$VERSION" ]; then
  bad "the VERSION file says '$FILE_VERSION' but you asked for '$VERSION'"
  die "Update the VERSION file and commit it, so the tag and the bundle agree."
fi
ok "VERSION file matches"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
[ -n "$DEVELOPER_ID" ] \
  || die "No Developer ID Application certificate. Run: make developer-id"
ok "$DEVELOPER_ID"

# The package needs its own certificate. Checked here rather than after the tests and two
# notarization round trips have already run.
INSTALLER_ID="$(security find-identity -v -p basic 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)"
[ -n "$INSTALLER_ID" ] \
  || die "No Developer ID Installer certificate — an unsigned package cannot be notarized. Run: make installer-id"
ok "$INSTALLER_ID"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "No notarization credentials for profile '$PROFILE'. Run: ./scripts/setup-notarization.sh"
ok "notarization credentials accepted"

# ---------------------------------------------------------------- build

bold "==> tests"
make test

bold "==> build and sign"
rm -rf "$DIST"
make app VERSION="$VERSION"

bold "==> notarize the app"
./scripts/notarize.sh "$APP"

bold "==> package"
# Both artefacts are cut from the stapled bundle, so each carries the ticket.
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
ok "$ZIP ($(du -h "$ZIP" | cut -f1))"

INSTALLER_IDENTITY="$INSTALLER_ID" ./scripts/make-pkg.sh "$APP" "$VERSION"

bold "==> notarize the installer"
# The package is a separate signed object; a notarized app inside an un-notarized installer still
# makes Gatekeeper refuse the installer.
./scripts/notarize.sh "$PKG"

bold "==> checksums"
( cd "$DIST" && shasum -a 256 "$(basename "$PKG")" "$(basename "$ZIP")" > "$(basename "$SUMS")" )
sed 's/^/  /' "$SUMS"

# ---------------------------------------------------------------- notes

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT

if [ -f CHANGELOG.md ] && grep -q "^## \[\?$VERSION\]\?" CHANGELOG.md; then
  # Everything between this version's heading and the next one.
  awk -v v="$VERSION" '
    $0 ~ "^## \\[?" v "\\]?" { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' CHANGELOG.md > "$NOTES_FILE"
  ok "notes taken from CHANGELOG.md"
else
  # Built from the commit log rather than with gh's --generate-notes: that flag cannot be combined
  # with --notes-file, and the install section below has to be in the notes either way.
  PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  {
    echo "## What's changed"
    echo
    if [ -n "$PREVIOUS_TAG" ]; then
      git log --no-merges --pretty='- %s' "$PREVIOUS_TAG..HEAD"
    else
      git log --no-merges --pretty='- %s'
    fi
  } > "$NOTES_FILE"
  ok "notes built from the commit log${PREVIOUS_TAG:+ since $PREVIOUS_TAG}"
fi

cat >> "$NOTES_FILE" <<NOTES

## Install

Download **$(basename "$PKG")** and open it. The installer puts Snapper in /Applications.

The app is signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper
warning. On first launch, grant **Screen Recording** in System Settings → Privacy & Security →
Screen & System Audio Recording, then relaunch — macOS only applies that permission to a fresh
launch.

Requires macOS 26 or later.

\`$(basename "$ZIP")\` is the same build as a zip archive.
NOTES

# ---------------------------------------------------------------- publish

bold "==> ready to publish"
cat <<SUMMARY
  tag:     $TAG
  commit:  $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)
  remote:  $(git remote get-url origin 2>/dev/null || echo "none")
  assets:  $(basename "$PKG")
           $(basename "$ZIP")
           $(basename "$SUMS")

This pushes the tag and publishes a public release. Both are visible immediately.
SUMMARY
read -r -p "  Publish? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || die "Stopped. Nothing was pushed; the artefacts are in $DIST/."

bold "==> tagging"
git tag -a "$TAG" -m "$NAME $VERSION"
git push origin "$TAG"
ok "pushed $TAG"

bold "==> publishing"
RELEASE_ARGS=(
  "$TAG"
  --title "$NAME $VERSION"
  --notes-file "$NOTES_FILE"
  --verify-tag
)
# A version with a suffix — 0.3.0-beta.1 — is published as a pre-release, which is exactly what
# the updater's "Include pre-releases" setting filters on.
case "$VERSION" in *-*) RELEASE_ARGS+=(--prerelease) ;; esac
RELEASE_ARGS+=("$PKG" "$ZIP" "$SUMS")

gh release create "${RELEASE_ARGS[@]}"

echo
printf '\033[32mreleased %s\033[0m\n' "$TAG"
gh release view "$TAG" --json url --jq .url
echo
echo "Verify the updater sees it:"
echo "  $APP/Contents/MacOS/$NAME --update-check"
