#!/usr/bin/env bash
set -euo pipefail
for dir in clusters/tinycloud/infrastructure/*/; do
  name="$(basename "$dir")"
  printf '%s\n' "--- $name"
  if kustomize build "$dir" > /dev/null; then
    printf '  ok\n'
  else
    printf '  FAIL\n'
    exit 1
  fi
done
