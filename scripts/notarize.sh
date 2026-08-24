#!/bin/bash
# Notarizes a signed .app or .dmg and staples Apple's ticket to it.
#
#   ./scripts/notarize.sh dist/Snapper.app
#   ./scripts/notarize.sh dist/Snapper-0.1.0.dmg
#
# Why stapling matters: notarization records a ticket on Apple's servers, and Gatekeeper will fetch
# it online — but a machine that is offline, or behind a filter, has no way to. Stapling writes the
# ticket into the bundle so the check succeeds without a network.
#
# An .app cannot be submitted as a directory, so it is zipped with `ditto` first (which preserves
# the symlinks and extended attributes a plain `zip` mangles). The ticket is then stapled to the
# original .app, not to the zip.
set -euo pipefail

TARGET="${1:-}"
PROFILE="${SNAPPER_NOTARY_PROFILE:-snapper-notary}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[ -n "$TARGET" ] || die "Usage: $0 <path to .app or .dmg>"
[ -e "$TARGET" ] || die "No such file: $TARGET"

xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found — update the Command Line Tools."

# A stored profile is what keeps the Apple ID password out of this script and out of the shell's
# history. Fail with the fix rather than with notarytool's own error.
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "No usable notarization credentials for profile '$PROFILE'. Run ./scripts/setup-notarization.sh first."

# ---------------------------------------------------------------- preflight

bold "==> checking the signature before submitting"
# Apple rejects submissions for reasons that are all visible locally, and a round trip takes
# minutes. Every one of these is a rejection if it fails.
SIGNING_INFO="$(codesign -dvvv "$TARGET" 2>&1 || true)"

if grep -q "Authority=Developer ID Application" <<<"$SIGNING_INFO"; then
  ok "$(grep -m1 'Authority=Developer ID Application' <<<"$SIGNING_INFO" | sed 's/Authority=//')"
else
  bad "not signed with a Developer ID Application certificate"
  echo
  echo "  Apple only notarizes code signed with a Developer ID. An ad-hoc or self-signed"
  echo "  signature cannot be notarized. Set one up with:"
  echo "      ./scripts/setup-developer-id.sh request"
  exit 1
fi

# The hardened runtime is a property of executable code, so it is required for an .app and
# meaningless for a disk image or installer package — those are containers. Demanding it everywhere
# made notarizing a DMG impossible, since `codesign` will not set the flag on one.
case "$TARGET" in
  *.app)
    if grep -q "flags=.*runtime" <<<"$SIGNING_INFO"; then
      ok "hardened runtime enabled"
    else
      bad "the hardened runtime is not enabled — Apple requires it for an app"
      echo "  Re-sign with:  codesign --force --options runtime --timestamp --sign \"Developer ID Application: ...\""
      exit 1
    fi
    ;;
  *)
    ok "container — hardened runtime does not apply (the app inside carries it)"
    ;;
esac

if grep -q "Timestamp=" <<<"$SIGNING_INFO"; then
  ok "signed with a secure timestamp"
else
  bad "no secure timestamp — Apple requires one (pass --timestamp to codesign)"
  exit 1
fi

case "$TARGET" in
  *.app)
    if codesign -d --entitlements - "$TARGET" 2>/dev/null | grep -q "get-task-allow"; then
      bad "the com.apple.security.get-task-allow entitlement is present — Apple rejects that"
      exit 1
    fi
    ok "no debug entitlement"
    ;;
esac

codesign --verify --deep --strict "$TARGET" 2>/dev/null \
  && ok "signature verifies" \
  || die "codesign --verify failed; fix the signature before submitting."

# ---------------------------------------------------------------- submit

case "$TARGET" in
  *.app)
    UPLOAD="$(dirname "$TARGET")/$(basename "$TARGET" .app)-notarize.zip"
    bold "==> zipping for submission"
    rm -f "$UPLOAD"
    # ditto, not zip: it keeps symlinks and extended attributes intact, which a .app needs.
    /usr/bin/ditto -c -k --keepParent "$TARGET" "$UPLOAD"
    echo "  $UPLOAD ($(du -h "$UPLOAD" | cut -f1))"
    CLEANUP_UPLOAD=1
    ;;
  *.dmg|*.pkg)
    UPLOAD="$TARGET"
    CLEANUP_UPLOAD=0
    ;;
  *)
    die "Can only notarize a .app, .dmg or .pkg — got $TARGET"
    ;;
esac

bold "==> submitting to Apple (this usually takes a few minutes)"
SUBMIT_LOG="$(mktemp)"
set +e
xcrun notarytool submit "$UPLOAD" \
  --keychain-profile "$PROFILE" \
  --wait \
  --timeout 30m 2>&1 | tee "$SUBMIT_LOG"
SUBMIT_STATUS=${PIPESTATUS[0]}
set -e

[ "${CLEANUP_UPLOAD:-0}" = "1" ] && rm -f "$UPLOAD"

REQUEST_ID="$(grep -m1 -o 'id: [0-9a-f-]\{36\}' "$SUBMIT_LOG" | head -1 | awk '{print $2}' || true)"

if [ "$SUBMIT_STATUS" -ne 0 ] || ! grep -q "status: Accepted" "$SUBMIT_LOG"; then
  bad "notarization did not succeed"
  if [ -n "$REQUEST_ID" ]; then
    echo
    bold "==> Apple's reasons"
    # The log is the only place that says *what* was wrong; the summary just says "Invalid".
    xcrun notarytool log "$REQUEST_ID" --keychain-profile "$PROFILE" 2>&1 | sed 's/^/  /'
  fi
  rm -f "$SUBMIT_LOG"
  exit 1
fi
ok "accepted by Apple${REQUEST_ID:+ (submission $REQUEST_ID)}"
rm -f "$SUBMIT_LOG"

# ---------------------------------------------------------------- staple

bold "==> stapling the ticket"
xcrun stapler staple "$TARGET" >/dev/null 2>&1 \
  && ok "stapled" \
  || die "stapling failed — the ticket may not have propagated yet; wait a minute and run: xcrun stapler staple \"$TARGET\""

# ---------------------------------------------------------------- verify

bold "==> verifying the way Gatekeeper will"
xcrun stapler validate "$TARGET" >/dev/null 2>&1 \
  && ok "ticket validates offline" \
  || bad "stapler validate failed"

case "$TARGET" in
  *.app) SPCTL_TYPE=exec ;;
  *)     SPCTL_TYPE=install ;;
esac

# This is the check that actually decides whether a first launch is blocked.
SPCTL_OUT="$(spctl --assess --type "$SPCTL_TYPE" -vvv "$TARGET" 2>&1 || true)"
if grep -q "accepted" <<<"$SPCTL_OUT"; then
  ok "Gatekeeper accepts it"
  grep -m1 "source=" <<<"$SPCTL_OUT" | sed 's/^/    /'
else
  bad "Gatekeeper assessment failed"
  sed 's/^/    /' <<<"$SPCTL_OUT"
  exit 1
fi

echo
printf '\033[32mnotarized: %s\033[0m\n' "$TARGET"
echo "It will now open on any Mac without a Gatekeeper warning, offline included."
