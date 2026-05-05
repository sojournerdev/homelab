#!/usr/bin/env bash
set -euo pipefail

KUBE_VERSION="${KUBE_VERSION:-1.35.3}"

# Build all kustomize overlays, then validate the rendered output.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Render each overlay into separate files
for dir in clusters/tinycloud/infrastructure/*/; do
  kustomize build "$dir" > "$tmpdir/$(basename "$dir").yaml" 2>/dev/null || true
done

# Combine with proper YAML document separators
> "$tmpdir/combined.yaml"
for f in "$tmpdir"/*.yaml; do
  cat "$f" >> "$tmpdir/combined.yaml"
  echo "---" >> "$tmpdir/combined.yaml"
done

# Include non-infrastructure manifests
for f in clusters/tinycloud/flux-system/gotk-components.yaml \
         clusters/tinycloud/flux-system/gotk-sync.yaml; do
  if [[ -f "$f" ]]; then
    cat "$f" >> "$tmpdir/combined.yaml"
    echo "---" >> "$tmpdir/combined.yaml"
  fi
done

exec kubeconform -strict -summary \
  -kubernetes-version "$KUBE_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -skip 'CustomResourceDefinition' \
  "$tmpdir/combined.yaml"
