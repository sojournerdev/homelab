#!/bin/sh
set -eu

cluster_name=${CLUSTER_NAME:-kind-tinycloud-ci}
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/tinycloud-ci.XXXXXX")
manifest_file=$temporary_dir/manifest.yaml
crd_file=$temporary_dir/crds.yaml
namespace_file=$temporary_dir/namespaces

cleanup() {
  status=$?
  rm -rf "$temporary_dir"
  ctlptl delete cluster "$cluster_name" >/dev/null 2>&1 || true
  exit "$status"
}

trap cleanup 0
trap 'exit 130' 2
trap 'exit 143' 15

ctlptl delete cluster "$cluster_name" >/dev/null 2>&1 || true
if ! ctlptl create cluster kind --name="$cluster_name"; then
  printf 'failed to create cluster: %s\n' "$cluster_name" >&2
  exit 1
fi
kubectl config use-context "$cluster_name"

if ! kustomize build clusters/tinycloud >"$manifest_file"; then
  printf '%s\n' 'failed to render cluster manifests' >&2
  exit 1
fi

yq 'select(.kind == "CustomResourceDefinition")' "$manifest_file" >"$crd_file"
kubectl apply --server-side --field-manager=ci -f "$crd_file"

yq -r 'select(.kind == "Namespace") | .metadata.name' "$manifest_file" >"$namespace_file"
while IFS= read -r namespace
do
  [ -n "$namespace" ] || continue
  kubectl create namespace "$namespace" \
    --dry-run=client \
    -o yaml \
    >"$temporary_dir/$namespace.yaml"
  kubectl apply --server-side --field-manager=ci \
    -f "$temporary_dir/$namespace.yaml"
done <"$namespace_file"

kubectl wait --for=condition=Established crd --all --timeout=120s
kubectl apply \
  --server-side \
  --dry-run=server \
  --validate=strict \
  --field-manager=ci \
  -f "$manifest_file"
