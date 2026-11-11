#!/bin/bash
# Creates a self-signed code-signing identity named "Jarvis Local Signing" in the login keychain.
# With it, every rebuild of Jarvis has the same signature, so macOS keeps the permissions you granted.
# Run once. macOS asks for your password to trust the certificate for code signing.
set -euo pipefail

NAME="Jarvis Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "The signing identity \"$NAME\" already exists. Nothing to do."
  exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cat > "$T/c.cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
CFG

# /usr/bin/openssl is LibreSSL. Its PKCS#12 output is the format `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$T/k.pem" -out "$T/c.pem" -config "$T/c.cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/j.p12" -passout pass:jarvis -name "$NAME"
security import "$T/j.p12" -k "$KEYCHAIN" -P jarvis -T /usr/bin/codesign
echo "macOS now asks for your password, to trust this certificate for code signing only."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$T/c.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Done. \"$NAME\" is ready."
else
  echo "The identity was imported but macOS does not list it as valid for code signing." >&2
  exit 1
fi
