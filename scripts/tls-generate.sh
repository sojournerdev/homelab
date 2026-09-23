#!/usr/bin/env bash
set -euo pipefail
umask 077

# Rotate the leaf certificate; keep the mkcert root CA stable.

SECRET="clusters/tinycloud/infrastructure/secrets.yaml"
CERT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gateway-tls.XXXXXX")"
CERT="$CERT_DIR/wildcard.home.arpa.pem"
KEY="$CERT_DIR/wildcard.home.arpa-key.pem"
PLAINTEXT="$CERT_DIR/secret.yaml"
ENCRYPTED="$CERT_DIR/secret.enc.yaml"

trap 'rm -rf "$CERT_DIR"' EXIT

# Reuse the existing root CA.
mise exec -- mkcert -install

mise exec -- mkcert \
  -cert-file "$CERT" \
  -key-file "$KEY" \
  '*.home.arpa'

mkdir -p "$(dirname "$SECRET")"
cat > "$PLAINTEXT" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gateway-tls
  namespace: envoy-gateway-system
type: kubernetes.io/tls
data:
  tls.crt: $(mise exec -- base64 < "$CERT" | tr -d '\n')
  tls.key: $(mise exec -- base64 < "$KEY" | tr -d '\n')
EOF

# Match .sops.yaml rules while keeping plaintext outside the repository.
mise exec -- sops encrypt \
  --filename-override "$SECRET" \
  --output "$ENCRYPTED" \
  "$PLAINTEXT"
mv "$ENCRYPTED" "$SECRET"

