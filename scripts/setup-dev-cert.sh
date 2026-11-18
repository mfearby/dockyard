#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate in your login keychain
# for local development builds. build-app.sh signs with it when present.
#
# Why: ad-hoc signatures change on every build, so macOS treats each build as a new app
# and forgets permissions such as Accessibility. A stable certificate keeps them.
#
# The certificate only signs code on this Mac. It isn't trusted by anyone else and
# can't be used for distribution. To remove it, delete "Dockyard Local Dev" in Keychain Access.
set -euo pipefail

NAME="Dockyard Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" is already in your login keychain."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT  # the private key only lives here until it's imported

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes a .p12 format that `security import` can read.
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
P12_PASS="$(uuidgen)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:"$P12_PASS"

# -T lets codesign use the key without prompting each time.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
echo "Added \"$NAME\" to your login keychain."
