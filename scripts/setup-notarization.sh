#!/bin/bash
# Stores the credentials `notarytool` needs, once, in the login keychain.
#
# Notarization is an authenticated request to Apple, and there are two ways to authenticate:
#
#   key        An App Store Connect API key: a .p8 private key, a Key ID, and an Issuer ID.
#              No password anywhere, revocable independently, and the only option that works
#              unattended in CI. Preferred.
#   password   An Apple ID plus an *app-specific password* — never the real Apple ID password.
#              Fewer moving parts if you have not made an API key before.
#
# Either way the secret goes straight into `notarytool store-credentials`, which keeps it in the
# login keychain under a profile name. Nothing is written into this repo, and no secret is echoed,
# logged, or passed on a command line where `ps` could see it.
set -euo pipefail

PROFILE="${SNAPPER_NOTARY_PROFILE:-snapper-notary}"
METHOD="${1:-}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

command -v xcrun >/dev/null || die "xcrun not found — install the Command Line Tools."
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found — update the Command Line Tools."

if [ -z "$METHOD" ]; then
  cat <<MENU

$(bold "How should notarytool authenticate?")

  1) App Store Connect API key   (recommended — no password, works in CI)
  2) Apple ID + app-specific password

MENU
  read -r -p "  [1/2] " choice
  case "$choice" in
    1) METHOD=key ;;
    2) METHOD=password ;;
    *) die "Pick 1 or 2." ;;
  esac
fi

# ---------------------------------------------------------------- API key

setup_key() {
  cat <<INTRO

$(bold "Create the API key first, in a browser:")

  1. Open  https://appstoreconnect.apple.com/access/integrations/api
  2. Team Keys > "+"
  3. Name it something like "Snapper notarization"
  4. Access: "Developer" is enough for notarization
  5. Generate, then download the .p8 file — Apple lets you download it exactly once
  6. Note the Key ID (next to the key) and the Issuer ID (above the list)

INTRO

  local keypath keyid issuer
  read -r -p "Path to the .p8 file: " keypath
  # Handles a path dragged in from Finder, which arrives quoted and with escaped spaces.
  keypath="${keypath%\"}"; keypath="${keypath#\"}"
  keypath="${keypath/#\~/$HOME}"
  keypath="$(printf '%s' "$keypath" | sed "s/\\\\ / /g")"
  [ -f "$keypath" ] || die "No such file: $keypath"

  read -r -p "Key ID: " keyid
  [ -n "$keyid" ] || die "A Key ID is required."
  echo "(Leave blank for an Individual key — notarytool only wants an Issuer ID for Team keys.)"
  read -r -p "Issuer ID: " issuer

  echo
  bold "==> storing credentials as profile '$PROFILE'"
  # --validate is the default, so Apple checks the key before anything is written.
  if [ -n "$issuer" ]; then
    xcrun notarytool store-credentials "$PROFILE" \
      --key "$keypath" --key-id "$keyid" --issuer "$issuer"
  else
    xcrun notarytool store-credentials "$PROFILE" \
      --key "$keypath" --key-id "$keyid"
  fi

  cat <<AFTER

$(bold "About that .p8 file:")

  notarytool has copied the key into your login keychain, so the file is no longer needed. It is
  the whole credential in plain text — keep it somewhere private or delete it, and never put it in
  this repo. (.gitignore covers *.p8, but do not rely on that.)

AFTER
}

# ---------------------------------------------------------------- app-specific password

setup_password() {
  # The Team ID is printed on the signing certificate, so there is no need to go looking for it.
  local team_guess
  team_guess="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o 'Developer ID Application: .*' | head -1 \
    | sed -n 's/.*(\([A-Z0-9]*\))".*/\1/p' || true)"

  cat <<INTRO

$(bold "Create an app-specific password first, in a browser:")

  1. Open  https://account.apple.com  and sign in
  2. Sign-In and Security > App-Specific Passwords > "+"
  3. Name it something like "Snapper notarization"
  4. Copy the password it shows you — it is only shown once

It looks like  abcd-efgh-ijkl-mnop  and is not your Apple ID password. It grants
notarization only, and you can revoke it from the same page at any time.

INTRO

  local apple_id team_id
  read -r -p "Apple ID email for your developer account: " apple_id
  [ -n "$apple_id" ] || die "An Apple ID is required."

  if [ -n "$team_guess" ]; then
    read -r -p "Team ID [$team_guess]: " team_id
    team_id="${team_id:-$team_guess}"
  else
    echo "(Your Team ID is the 10-character code at https://developer.apple.com/account under Membership.)"
    read -r -p "Team ID: " team_id
  fi
  [ -n "$team_id" ] || die "A Team ID is required."

  echo
  bold "==> storing credentials as profile '$PROFILE'"
  echo "notarytool will now ask for the app-specific password. It is not shown as you type."
  echo
  # notarytool prompts for the password itself and never echoes it, so it is neither passed on the
  # command line (where `ps` would show it) nor held in a shell variable here.
  xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$apple_id" \
    --team-id "$team_id"
}

case "$METHOD" in
  key)      setup_key ;;
  password) setup_password ;;
  *)        die "Unknown method '$METHOD' — expected 'key' or 'password'." ;;
esac

echo
bold "==> verifying the credentials work"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  printf '\033[32m  credentials accepted by Apple\033[0m\n'
else
  die "Apple rejected those credentials. Check the IDs, and that the key has at least Developer access."
fi

cat <<NEXT

Done. The profile lives in your login keychain, not in this repo.

Next:
  make notarize     # build, sign with Developer ID, notarize, staple
  make release      # the above, plus an installer and a GitHub release

NEXT
