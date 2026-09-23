#!/usr/bin/env bash
set -euo pipefail

# Always regenerates cert and re-encrypts. Idempotent — safe to run anytime.
# Re-encryption changes the SOPS output (new nonce) but the cert is unchanged.

SECRET="clusters/tinycloud/infrastructure/secrets.yaml"
DOMAIN="*.internal"
CERT=".certs/${DOMAIN}.pem"
KEY=".certs/${DOMAIN}-key.pem"

trap 'rm -rf .certs' EXIT

mkcert -install

mkdir -p .certs
mkcert -cert-file "$CERT" -key-file "$KEY" "$DOMAIN"

mkdir -p "$(dirname "$SECRET")"
cat > "$SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gateway-tls
  namespace: envoy-gateway-system
type: kubernetes.io/tls
data:
  tls.crt: $(base64 < "$CERT")
  tls.key: $(base64 < "$KEY")
EOF

sops -e -i "$SECRET"
