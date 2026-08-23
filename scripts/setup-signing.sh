#!/bin/bash
# Creates a self-signed code-signing identity so Screen Recording permission survives rebuilds.
#
# Why this exists: macOS ties TCC permissions to an app's designated requirement. Ad-hoc signing
# produces `cdhash H"..."`, which changes with every build, so each rebuild looks like a brand new
# app and the permission prompt returns. Signing with a stable certificate produces
# `identifier "..." and certificate root H"..."` instead, which does not change.
#
# The identity lives in its own keychain rather than your login keychain, purely so the key's
# access control can be authorised here instead of via a modal dialog on every build. The keychain
# password is generated locally and used only to unlock that keychain.
set -euo pipefail

NAME="${1:-Snapper Dev}"
KEYCHAIN="snapper-signing.keychain"
SIGN_DIR="$HOME/Library/Application Support/com.zikopoulos.snapper/signing"
PWFILE="$SIGN_DIR/keychain-password"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$SIGN_DIR"; chmod 700 "$SIGN_DIR"

echo "==> generating a code-signing certificate for '$NAME'"
cat > "$WORK/cert.conf" <<CONF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3_codesign
[ dn ]
CN = $NAME
O  = Snapper Local Development
[ v3_codesign ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
CONF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -config "$WORK/cert.conf" -extensions v3_codesign 2>/dev/null

# A transient passphrase for a bundle that is deleted when this script exits. macOS rejects
# PKCS#12 files written with an empty password, hence a non-empty one.
#
# The PBE algorithms are pinned rather than left to the default. OpenSSL 3 (e.g. Homebrew's, which
# can precede /usr/bin/openssl on PATH) defaults to AES-256-CBC + PBKDF2, which Security.framework
# cannot read -- `security import` fails with "Unknown format in import." PBE-SHA1-3DES is what it
# accepts, and both OpenSSL 3 and LibreSSL write it.
openssl pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:transient -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> creating keychain"
# `tr -dc ... < /dev/urandom | head -c 32` makes head close the pipe while tr is still writing,
# which kills tr with SIGPIPE and, under `set -o pipefail`, fails the script with exit 141.
# openssl is already required above, and cut consumes all of its input, so nothing gets signalled.
KCPASS="$(openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32)"
if [ "${#KCPASS}" -ne 32 ]; then
  echo "failed to generate a 32-character keychain password" >&2
  exit 1
fi
printf '%s' "$KCPASS" > "$PWFILE"; chmod 600 "$PWFILE"

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KCPASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # never auto-lock
security unlock-keychain -p "$KCPASS" "$KEYCHAIN"

echo "==> importing identity"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P transient -T /usr/bin/codesign -A >/dev/null

# Authorises codesign to use the key now, so no dialog interrupts a later build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null 2>&1

echo "==> adding to the keychain search list"
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' | grep -v "$KEYCHAIN" || true)"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo
security find-identity -p codesigning "$KEYCHAIN" | sed -n '2p'
echo
echo "Done. Rebuild and reinstall with:  make install"
echo "Then grant Screen Recording once more — it will stick from then on."
