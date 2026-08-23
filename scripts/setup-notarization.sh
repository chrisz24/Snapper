#!/bin/bash
# Stores the credentials `notarytool` needs, once, in the login keychain.
#
# Notarization is an authenticated request to Apple. It needs three things: the Apple ID that owns
# the developer account, that account's Team ID, and an *app-specific password* — never the real
# Apple ID password. This script hands all three straight to `notarytool store-credentials`, which
# keeps them in the login keychain under a profile name; nothing is written to this repo, and no
# password is echoed or logged.
set -euo pipefail

PROFILE="${SNAPPER_NOTARY_PROFILE:-snapper-notary}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

command -v xcrun >/dev/null || die "xcrun not found — install the Command Line Tools."
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found — update the Command Line Tools."

# The Team ID is printed on the certificate, so there is no need to go looking for it.
TEAM_GUESS="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o 'Developer ID Application: .*' | head -1 \
  | sed -n 's/.*(\([A-Z0-9]*\))".*/\1/p' || true)"

cat <<INTRO

$(bold "Before continuing, create an app-specific password:")

  1. Open  https://account.apple.com  and sign in
  2. Sign-In and Security > App-Specific Passwords > "+"
  3. Name it something like "Snapper notarization"
  4. Copy the password it shows you — it is only shown once

It looks like  abcd-efgh-ijkl-mnop  and is not your Apple ID password. It grants
notarization only, and you can revoke it from the same page at any time.

INTRO

read -r -p "Apple ID email for your developer account: " APPLE_ID
[ -n "$APPLE_ID" ] || die "An Apple ID is required."

if [ -n "$TEAM_GUESS" ]; then
  read -r -p "Team ID [$TEAM_GUESS]: " TEAM_ID
  TEAM_ID="${TEAM_ID:-$TEAM_GUESS}"
else
  echo "(Your Team ID is the 10-character code at https://developer.apple.com/account under Membership.)"
  read -r -p "Team ID: " TEAM_ID
fi
[ -n "$TEAM_ID" ] || die "A Team ID is required."

echo
bold "==> storing credentials as profile '$PROFILE'"
echo "notarytool will now ask for the app-specific password. It is not shown as you type."
echo

# notarytool prompts for the password itself and never echoes it, so it is neither passed on the
# command line (where `ps` would show it) nor held in a shell variable here.
xcrun notarytool store-credentials "$PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID"

echo
bold "==> verifying the credentials work"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  printf '\033[32m  credentials accepted by Apple\033[0m\n'
else
  die "Apple rejected those credentials. Check the Apple ID, the Team ID, and that the password is an app-specific one."
fi

cat <<NEXT

Done. The profile lives in your login keychain, not in this repo.

Next:
  make notarize     # build, sign with Developer ID, notarize, staple
  make release      # the above, plus a DMG and a GitHub release

NEXT
