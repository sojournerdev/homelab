#!/usr/bin/env bash
set -euo pipefail

artifact_dir=".cache/cluster-artifact"

schema_dir="$(mktemp -d "${TMPDIR:-/tmp}/homelab-flux-schema.XXXXXX")"
# shellcheck disable=SC2329
cleanup() {
  rm -rf -- "$schema_dir"
}
trap cleanup EXIT

kustomize build "$artifact_dir/crds" \
  | flux schema extract crd --output-dir "$schema_dir" >/dev/null

kustomize build "$artifact_dir" \
  | flux schema validate \
      --schema-location "$schema_dir" \
      --schema-location default \
      --schema-location ecosystem
