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
PWFILE="$SIGN_DIR/keychain-password"

# Two certificates are needed to ship a signed, notarized installer, and they are different types
# from the same account:
#
#   application   "Developer ID Application" — signs Snapper.app
#   installer     "Developer ID Installer"   — signs the .pkg
#
# Each needs its own key and its own signing request; a certificate issued for one cannot sign the
# other. KIND selects which one this run is dealing with.
KIND="application"
KEYFILE=""
CSRFILE=""

set_kind() {
  case "${1:-application}" in
    application|app)   KIND="application" ;;
    installer|pkg)     KIND="installer" ;;
    *) die "Unknown certificate kind '${1}' — expected 'application' or 'installer'." ;;
  esac
  KEYFILE="$SIGN_DIR/developer-id-$KIND.key"
  CSRFILE="$SIGN_DIR/developer-id-$KIND.certSigningRequest"
}
INTERMEDIATE_URL="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"

# Scratch space for the PKCS#12 bundle, which contains the private key in cleartext. Declared at
# file scope, not inside a function: a trap registered against a `local` runs after that local has
# gone out of scope, so under `set -u` the cleanup aborts and the key material is left behind.
WORK=""
cleanup() { [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM

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

  local portal_choice download_name
  if [ "$KIND" = "installer" ]; then
    portal_choice='Software > "Developer ID Installer"'
    download_name="developerID_installer.cer"
  else
    portal_choice='Software > "Developer ID Application"'
    download_name="developerID_application.cer"
  fi

  cat <<INSTRUCTIONS

$(bold "Next, in a browser:")

  1. Open  https://developer.apple.com/account/resources/certificates/add
  2. Choose  $portal_choice
  3. Profile Type: "G2 Sub-CA (Xcode 11.4.1 or later)"
  4. Upload this file:

       $CSRFILE

     (revealed in Finder for you now)

  5. Download the certificate it produces — usually to ~/Downloads
  6. Come back and run:

       ./scripts/setup-developer-id.sh import ~/Downloads/$download_name

INSTRUCTIONS
  open -R "$CSRFILE" 2>/dev/null || true
}

# ---------------------------------------------------------------- import

import() {
  local cer="${1:-}"
  [ -n "$cer" ] || die "Usage: $0 import <path to the .cer Apple issued>"
  [ -f "$cer" ] || die "No such file: $cer"
  # The key is checked *after* the certificate's kind is read, further down: which key has to match
  # depends on which kind this is, and checking here would test whichever kind happened to be the
  # default.

  WORK="$(mktemp -d)"; chmod 700 "$WORK"

  bold "==> reading the certificate"
  # The portal hands back DER; openssl needs to be told, and this also validates the file.
  if ! openssl x509 -inform DER -in "$cer" -out "$WORK/cert.pem" 2>/dev/null; then
    openssl x509 -inform PEM -in "$cer" -out "$WORK/cert.pem" 2>/dev/null \
      || die "That does not look like a certificate."
  fi
  local subject; subject="$(openssl x509 -in "$WORK/cert.pem" -noout -subject 2>/dev/null || true)"
  echo "  $subject"
  # Infer the kind from the certificate itself rather than trusting the argument, so importing an
  # installer certificate cannot silently be matched against the application key.
  case "$subject" in
    *"Developer ID Application"*) set_kind application ;;
    *"Developer ID Installer"*)   set_kind installer ;;
    *) printf '  \033[33mwarning\033[0m: this is neither a "Developer ID Application" nor a "Developer ID Installer" certificate.\n'
       echo "  Those are the only two that matter for distributing outside the App Store."
       read -r -p "  Import it anyway? [y/N] " reply
       [[ "$reply" =~ ^[Yy]$ ]] || die "Stopped." ;;
  esac
  echo "  kind: Developer ID $KIND"
  [ -f "$KEYFILE" ] || die "No private key at $KEYFILE — run '$0 request $KIND' first."

  # Fail early rather than after importing: a key/certificate mismatch is the usual outcome of
  # re-running 'request' between downloading and importing.
  local keymod certmod
  keymod="$(openssl rsa -in "$KEYFILE" -noout -modulus 2>/dev/null)"
  certmod="$(openssl x509 -in "$WORK/cert.pem" -noout -modulus 2>/dev/null)"
  [ "$keymod" = "$certmod" ] \
    || die "This certificate was not issued for the key in $KEYFILE. Run '$0 request $KIND' and upload that CSR."

  bold "==> bundling key and certificate"
  # PBE-SHA1-3DES is pinned because Security.framework cannot read OpenSSL 3's AES-256-CBC/PBKDF2
  # default — `security import` rejects it with "Unknown format in import."
  openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$KEYFILE" -in "$WORK/cert.pem" \
    -passout pass:transient -name "Snapper Developer ID $KIND" \
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
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P transient -T /usr/bin/codesign -A >/dev/null
  # Authorises codesign up front so no modal dialog interrupts a build.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kcpass" "$KEYCHAIN" >/dev/null 2>&1

  ensure_intermediate "$kcpass"

  echo
  bold "==> identities now available"
  # An installer certificate is not a *code-signing* identity, so -p codesigning does not list it.
  # Querying both policies is the only way to show what was actually imported.
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | sed -n 's/^ *[0-9]) /  /p'
  security find-identity -v -p basic "$KEYCHAIN" 2>/dev/null \
    | grep -i "Developer ID Installer" | sed -n 's/^ *[0-9]) /  /p'

  local team
  team="$(security find-identity -v -p codesigning "$KEYCHAIN" \
          | grep -o 'Developer ID Application: .*' | head -1 | sed -n 's/.*(\([A-Z0-9]*\))".*/\1/p')"
  echo
  if [ -n "$team" ]; then
    bold "Your Team ID is $team — you will need it in the next step."
  fi
  echo
  if xcrun notarytool history --keychain-profile "${SNAPPER_NOTARY_PROFILE:-snapper-notary}" >/dev/null 2>&1; then
    echo "Notarization credentials are already stored. Next:"
    echo "  make pkg          # build a signed installer"
    echo "  make release      # test, notarize, package, publish"
  else
    echo "Next:"
    echo "  make notary-setup # store the credentials notarytool needs"
    echo "  make release      # test, notarize, package, publish"
  fi
  echo
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
  # Nothing secret here — a public CA certificate — but leaving temp dirs around is still untidy.
}

# ---------------------------------------------------------------- status

status() {
  bold "keychain"
  if security list-keychains -d user | grep -q "$KEYCHAIN"; then
    echo "  $KEYCHAIN is in the search list"
  else
    echo "  $KEYCHAIN does not exist yet"
  fi
  bold "keys"
  for kind in application installer; do
    local f="$SIGN_DIR/developer-id-$kind.key"
    [ -f "$f" ] && echo "  $kind: $f" || echo "  $kind: none — run '$0 request $kind'"
  done
  bold "identities that can sign code (the app)"
  security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^ *[0-9]) /  /p' \
    || echo "  none"
  bold "identities that can sign installers (the pkg)"
  security find-identity -v -p basic 2>/dev/null | grep -i "Developer ID Installer" | sed 's/^/  /' \
    || echo "  none — run '$0 request installer'"
}

case "${1:-}" in
  request) set_kind "${2:-application}"; request ;;
  import)  set_kind application; import "${2:-}" ;;
  status)  set_kind application; status ;;
  *) cat <<USAGE
Usage:
  $0 request [application|installer]   generate a key and a CSR to upload to Apple
  $0 import <file.cer>                 import the certificate Apple issued (kind is detected)
  $0 status                            show what is set up so far

"application" signs Snapper.app. "installer" signs the .pkg. Shipping a notarized
installer needs both; they are separate certificates from the same Apple account.
USAGE
     exit 1 ;;
esac
