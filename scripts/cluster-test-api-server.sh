#!/usr/bin/env bash
set -euo pipefail

cluster_name="kind-homelab-api-server"
field_manager="homelab-api-server-validation"
artifact_dir=".cache/cluster-artifact"
kubeconfig="$(mktemp "${TMPDIR:-/tmp}/homelab-kubeconfig.XXXXXX")"
export KUBECONFIG="$kubeconfig"

cluster_created=0
# shellcheck disable=SC2329
cleanup() {
  if (( cluster_created )); then
    ctlptl delete -f tests/api-server/ctlptl.yaml >/dev/null 2>&1 || true
  fi
  rm -f -- "$kubeconfig"
}
trap cleanup EXIT

ctlptl apply -f tests/api-server/ctlptl.yaml
cluster_created=1

kubectl --context "$cluster_name" apply \
  --server-side \
  --field-manager "$field_manager" \
  -f "$artifact_dir/flux-system/gotk-components.yaml"

kubectl --context "$cluster_name" apply \
  --server-side \
  --field-manager "$field_manager" \
  -k "$artifact_dir/crds"

kubectl --context "$cluster_name" wait \
  --for=condition=Established \
  --timeout=60s \
  crd --all

for ns in gateway-system gpu-system metallb-system inference; do
  kubectl --context "$cluster_name" create namespace "$ns" \
    --dry-run=client -o yaml \
    | kubectl --context "$cluster_name" apply --server-side -f -
done

kustomize build "$artifact_dir/infrastructure" \
  | kubectl --context "$cluster_name" apply \
      --server-side \
      --dry-run=server \
      --validate=strict \
      --field-manager "$field_manager" \
      -f -

kustomize build "$artifact_dir/apps" \
  | kubectl --context "$cluster_name" apply \
      --server-side \
      --dry-run=server \
      --validate=strict \
      --field-manager "$field_manager" \
      -f -
