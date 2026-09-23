#!/usr/bin/env bash
set -euo pipefail

cluster_dir="clusters/tinycloud"
schema_config=".fluxschema.yml"

flux build kustomization infrastructure \
  --path "$cluster_dir/infrastructure" \
  --kustomization-file "$cluster_dir/infrastructure.yaml" \
  --dry-run \
  | flux schema validate --config "$schema_config"

flux build kustomization apps \
  --path "$cluster_dir/apps" \
  --kustomization-file "$cluster_dir/apps.yaml" \
  --dry-run \
  | flux schema validate --config "$schema_config"
