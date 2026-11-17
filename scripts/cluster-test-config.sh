#!/bin/sh
set -eu

cluster_dir=clusters/tinycloud
schema_config=.fluxschema.yml
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/tinycloud-schema.XXXXXX")

cleanup() {
  status=$?
  rm -rf "$temporary_dir"
  exit "$status"
}

trap cleanup 0
trap 'exit 130' 2
trap 'exit 143' 15

validate_file() {
  name=$1
  path=$2
  kustomization_file=$3
  rendered_file=$temporary_dir/$name.yaml

  if ! flux build kustomization "$name" \
    --path "$path" \
    --kustomization-file "$kustomization_file" \
    --dry-run >"$rendered_file"; then
    printf '%s\n' "flux build failed for $name" >&2
    return 1
  fi

  flux schema validate --config "$schema_config" <"$rendered_file"
}

root_file=$temporary_dir/root.yaml
if ! kustomize build "$cluster_dir" >"$root_file"; then
  printf '%s\n' "kustomize build failed for $cluster_dir" >&2
  exit 1
fi
flux schema validate --config "$schema_config" <"$root_file"

validate_file infrastructure \
  "$cluster_dir/infrastructure" \
  "$cluster_dir/infrastructure.yaml"

validate_file platform \
  "$cluster_dir/platform" \
  "$cluster_dir/platform.yaml"
  