#!/bin/sh
set -eu

: "${KUBE_CONTEXT:?KUBE_CONTEXT must be set to the target Kubernetes context}"

flux reconcile kustomization flux-system \
  --namespace flux-system \
  --with-source \
  --context "$KUBE_CONTEXT"
