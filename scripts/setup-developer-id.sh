#!/bin/bash
# Gets a Developer ID Application certificate onto this machine without Xcode.
#
# Notarization needs a certificate issued by Apple; the self-signed one from `make cert` cannot be
# notarized, only run locally. Xcode normally handles the key/CSR/import dance, but there is no
# Xcode here, so this does it with openssl and `security` in two passes:
#
#   ./scripts/setup-developer-id.sh request              # makes a key and a CSR to upload
#   ./scripts/setup-developer-id.sh import <file.cer>    # imports what Apple gives back
#
# The private key never leaves this machine — Apple only ever sees the CSR.
#
# The identity lives in its own keychain, separate from the self-signed one, so `make cert-remove`
# cannot take the distribution key with it.
set -euo pipefail

KEYCHAIN="snapper-distribution.keychain"
SIGN_DIR="$HOME/Library/Application Support/com.zikopoulos.snapper/distribution"
KEYFILE="$SIGN_DIR/developer-id.key"
CSRFILE="$SIGN_DIR/developer-id.certSigningRequest"
PWFILE="$SIGN_DIR/keychain-password"
INTERMEDIATE_URL="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

mkdir -p "$SIGN_DIR"; chmod 700 "$SIGN_DIR"

# ---------------------------------------------------------------- request

request() {
  if [ -f "$KEYFILE" ]; then
    bold "A key already exists at:"
    echo "  $KEYFILE"
    echo
    read -r -p "Replace it? Any certificate already issued for it becomes unusable. [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Left alone. Re-run with 'import' if you already have a .cer."
  fi

  # An email address and common name are required by the portal but are not what identifies the
  # certificate — the team the Apple ID belongs to is.
  local email name
  read -r -p "Apple ID email for your developer account: " email
  [ -n "$email" ] || die "An email address is required."
  read -r -p "Your name, as it should appear in the certificate: " name
  [ -n "$name" ] || die "A name is required."

  echo
  bold "==> generating a 2048-bit key and a certificate signing request"
  # Apple's portal rejects anything other than 2048-bit RSA.
  openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -keyout "$KEYFILE" -out "$CSRFILE" \
    -subj "/emailAddress=$email/CN=$name/C=US" 2>/dev/null
  chmod 600 "$KEYFILE"

  cat <<INSTRUCTIONS

$(bold "Next, in a browser:")

  1. Open  https://developer.apple.com/account/resources/certificates/add
  2. Choose  Software > "Developer ID Application"
  3. Profile Type: "G2 Sub-CA (Xcode 11.4.1 or later)"
  4. Upload this file:

       $CSRFILE

     (revealed in Finder for you now)

  5. Download the certificate it produces — usually to ~/Downloads
  6. Come back and run:

       ./scripts/setup-developer-id.sh import ~/Downloads/developerID_application.cer

INSTRUCTIONS
  open -R "$CSRFILE" 2>/dev/null || true
}

# ---------------------------------------------------------------- import

import() {
  local cer="${1:-}"
  [ -n "$cer" ] || die "Usage: $0 import <path to the .cer Apple issued>"
  [ -f "$cer" ] || die "No such file: $cer"
  [ -f "$KEYFILE" ] || die "No private key at $KEYFILE — run '$0 request' first."

  local work; work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

  bold "==> reading the certificate"
  # The portal hands back DER; openssl needs to be told, and this also validates the file.
  if ! openssl x509 -inform DER -in "$cer" -out "$work/cert.pem" 2>/dev/null; then
    openssl x509 -inform PEM -in "$cer" -out "$work/cert.pem" 2>/dev/null \
      || die "That does not look like a certificate."
  fi
  local subject; subject="$(openssl x509 -in "$work/cert.pem" -noout -subject 2>/dev/null || true)"
  echo "  $subject"
  case "$subject" in
    *"Developer ID Application"*) ;;
    *) printf '  \033[33mwarning\033[0m: this is not a "Developer ID Application" certificate.\n'
       echo "  Only that kind can notarize an app distributed outside the App Store."
       read -r -p "  Import it anyway? [y/N] " reply
       [[ "$reply" =~ ^[Yy]$ ]] || die "Stopped." ;;
  esac

  # Fail early rather than after importing: a key/certificate mismatch is the usual outcome of
  # re-running 'request' between downloading and importing.
  local keymod certmod
  keymod="$(openssl rsa -in "$KEYFILE" -noout -modulus 2>/dev/null)"
  certmod="$(openssl x509 -in "$work/cert.pem" -noout -modulus 2>/dev/null)"
  [ "$keymod" = "$certmod" ] \
    || die "This certificate was not issued for the key in $KEYFILE. Run '$0 request' and upload the new CSR."

  bold "==> bundling key and certificate"
  # PBE-SHA1-3DES is pinned because Security.framework cannot read OpenSSL 3's AES-256-CBC/PBKDF2
  # default — `security import` rejects it with "Unknown format in import."
  openssl pkcs12 -export -out "$work/identity.p12" \
    -inkey "$KEYFILE" -in "$work/cert.pem" \
    -passout pass:transient -name "Snapper Developer ID" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

  local kcpass
  # Tested by looking at the search list rather than with `security show-keychain-info`, which
  # raises a GUI password prompt when the keychain is locked or missing.
  if [ -f "$PWFILE" ] && security list-keychains -d user | grep -q "$KEYCHAIN"; then
    kcpass="$(cat "$PWFILE")"
    security unlock-keychain -p "$kcpass" "$KEYCHAIN"
  else
    bold "==> creating keychain $KEYCHAIN"
    kcpass="$(openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32)"
    [ "${#kcpass}" -eq 32 ] || die "Could not generate a keychain password."
    printf '%s' "$kcpass" > "$PWFILE"; chmod 600 "$PWFILE"
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    security create-keychain -p "$kcpass" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"        # never auto-lock
    security unlock-keychain -p "$kcpass" "$KEYCHAIN"

    local existing
    existing="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' | grep -v "$KEYCHAIN" || true)"
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $existing
  fi

  bold "==> importing the identity"
  security import "$work/identity.p12" -k "$KEYCHAIN" -P transient -T /usr/bin/codesign -A >/dev/null
  # Authorises codesign up front so no modal dialog interrupts a build.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kcpass" "$KEYCHAIN" >/dev/null 2>&1

  ensure_intermediate "$kcpass"

  echo
  bold "==> identities now available"
  security find-identity -v -p codesigning "$KEYCHAIN" | sed 's/^/  /'

  local team
  team="$(security find-identity -v -p codesigning "$KEYCHAIN" \
          | grep -o 'Developer ID Application: .*' | head -1 | sed -n 's/.*(\([A-Z0-9]*\))".*/\1/p')"
  echo
  if [ -n "$team" ]; then
    bold "Your Team ID is $team — you will need it in the next step."
  fi
  cat <<NEXT

Next:
  ./scripts/setup-notarization.sh     # store the credentials notarytool needs
  make notarize                      # build, sign, notarize, staple

NEXT
}

# Without Apple's intermediate certificate, codesign cannot build a chain to a trusted root and
# fails with "unable to build chain". Xcode installs it; here it has to be fetched once.
ensure_intermediate() {
  local kcpass="$1"
  if security find-certificate -c "Developer ID Certification Authority" "$KEYCHAIN" >/dev/null 2>&1 \
     || security find-certificate -c "Developer ID Certification Authority" >/dev/null 2>&1; then
    echo "  Apple's Developer ID intermediate is already present."
    return
  fi

  echo
  bold "==> Apple's Developer ID intermediate certificate is missing"
  echo "  Without it, codesign cannot build a certificate chain and signing fails."
  echo "  It is a public certificate, downloaded from Apple:"
  echo "    $INTERMEDIATE_URL"
  read -r -p "  Download and add it to $KEYCHAIN? [Y/n] " reply
  if [[ "$reply" =~ ^[Nn]$ ]]; then
    echo "  Skipped. Add it by hand if signing fails with 'unable to build chain'."
    return
  fi

  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "$INTERMEDIATE_URL" -o "$tmp/DeveloperIDG2CA.cer"; then
    security import "$tmp/DeveloperIDG2CA.cer" -k "$KEYCHAIN" >/dev/null 2>&1 \
      && echo "  added." \
      || echo "  already present."
  else
    echo "  download failed — add it by hand from $INTERMEDIATE_URL if signing fails."
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------- status

status() {
  bold "keychain"
  if security list-keychains -d user | grep -q "$KEYCHAIN"; then
    echo "  $KEYCHAIN is in the search list"
  else
    echo "  $KEYCHAIN does not exist yet"
  fi
  bold "key"
  [ -f "$KEYFILE" ] && echo "  $KEYFILE" || echo "  none — run '$0 request'"
  bold "signing identities visible to codesign"
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
}

case "${1:-}" in
  request) request ;;
  import)  import "${2:-}" ;;
  status)  status ;;
  *) cat <<USAGE
Usage:
  $0 request                  generate a key and a CSR to upload to Apple
  $0 import <file.cer>        import the certificate Apple issued
  $0 status                   show what is set up so far
USAGE
     exit 1 ;;
esac
