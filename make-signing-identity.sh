#!/bin/bash
# Creates a self-signed code-signing certificate named "GestureBind Local Dev" in the
# login keychain, so rebuilds keep a stable code signature.
#
# Why this matters: an ad-hoc signature has no team identifier, so macOS keys TCC
# permissions (Screen Recording, Accessibility) to the binary's cdhash. That changes on
# every build, making each rebuild look like a brand-new app that has to be granted
# permission all over again. A certificate gives the bundle a designated requirement of
# "identifier + certificate leaf", which does not change when the code does.
#
# Run once. macOS may ask for your login password to trust the certificate.
set -euo pipefail

IDENTITY="GestureBind Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$IDENTITY" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" 2>/dev/null

# The `security` tool cannot read OpenSSL 3's default PKCS#12 encryption, hence -legacy.
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -legacy -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
    -passout pass:gesturebind 2>/dev/null

security import "$TMP/id.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -A -P gesturebind
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created signing identity '$IDENTITY'."
