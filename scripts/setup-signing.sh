#!/usr/bin/env bash
set -euo pipefail

# Creates a stable self-signed code-signing identity in your login keychain.
#
# Why: ad-hoc signed apps are identified by macOS purely by their binary hash, so
# Accessibility and Microphone grants stop applying after every rebuild. Signing
# with a real certificate keys those grants to the certificate + bundle ID
# instead, so they survive rebuilds.
#
# You only need to run this once. It may ask for your login password when it
# marks the new certificate as trusted for code signing.

IDENTITY_NAME="${RICHARD_POTATO_IDENTITY:-Richard Potato Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$IDENTITY_NAME"; then
  echo "Signing identity '$IDENTITY_NAME' already exists. Nothing to do."
  exit 0
fi

echo "Creating self-signed code-signing identity: $IDENTITY_NAME"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3

[ dn ]
CN = $IDENTITY_NAME

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" \
  -out "$WORK/cert.pem" \
  -config "$WORK/cert.conf" 2>/dev/null

# Apple's `security import` cannot read OpenSSL 3's default PKCS#12 encoding,
# so pin the older SHA1/3DES algorithms it does understand.
P12_PASSWORD="richard-potato-temp"
if ! openssl pkcs12 -export \
  -inkey "$WORK/key.pem" \
  -in "$WORK/cert.pem" \
  -name "$IDENTITY_NAME" \
  -out "$WORK/identity.p12" \
  -macalg sha1 \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -passout "pass:$P12_PASSWORD" 2>/dev/null; then
  echo "Retrying PKCS#12 export with the legacy provider..."
  openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" \
    -in "$WORK/cert.pem" \
    -name "$IDENTITY_NAME" \
    -out "$WORK/identity.p12" \
    -passout "pass:$P12_PASSWORD"
fi

echo "Importing into $KEYCHAIN..."
security import "$WORK/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

echo "Marking the certificate as trusted for code signing (may prompt for your password)..."
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$WORK/cert.pem"

# Let codesign use the private key without prompting on every build. This needs
# the keychain password, so it is best-effort; if it fails, macOS will ask once
# and you can choose "Always Allow".
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
if security find-identity -v -p codesigning | grep -qF "$IDENTITY_NAME"; then
  echo "Done. '$IDENTITY_NAME' is now a valid code-signing identity."
  echo "./scripts/dev.sh and ./scripts/release.sh will use it automatically."
  echo
  echo "One-time step: because the app's code identity changed, remove Richard Potato"
  echo "from System Settings -> Privacy & Security -> Accessibility and add it once more."
  echo "After that the grant will persist across rebuilds."
else
  echo "The identity was created but is not showing as valid for code signing." >&2
  echo "Open Keychain Access, find '$IDENTITY_NAME', and set its trust for" >&2
  echo "Code Signing to 'Always Trust'." >&2
  exit 1
fi
