#!/bin/sh
set -eu

script_dir=$(dirname "$0")
script_dir=$(CDPATH=; cd "$script_dir" && pwd)
repository_dir=$(dirname "$script_dir")

: "${KUBE_CONTEXT:?KUBE_CONTEXT must be set to the target Kubernetes context}"
: "${CLUSTER_DIR:?CLUSTER_DIR must be set to the cluster configuration directory}"
: "${HELM_TIMEOUT:?HELM_TIMEOUT must be set to a Helm timeout, such as 5m}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required command not found: %s\n' "$1" >&2
    exit 1
  }
}

configure_helm_repositories() {
  helm repo add metallb https://metallb.github.io/metallb --force-update
  helm repo add nvidia-device-plugin https://nvidia.github.io/k8s-device-plugin --force-update
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  helm repo add zot https://zotregistry.dev/helm-charts --force-update
}

install_chart() {
  helm --kube-context "$KUBE_CONTEXT" upgrade --install "$1" "$2" \
    --namespace "$3" \
    --create-namespace \
    --version "$4" \
    --values "$5" \
    --wait \
    --timeout "$HELM_TIMEOUT"
}

wait_for_rollout() {
  resource=$1
  namespace=$2

  kubectl --context "$KUBE_CONTEXT" rollout status "$resource" \
    --namespace "$namespace" \
    --timeout=120s
}

main() {
  cd "$repository_dir"

  for tool in kubectl helm; do
    require_command "$tool"
  done

  kubectl config get-contexts "$KUBE_CONTEXT" >/dev/null 2>&1 || {
    printf 'Kubernetes context not found: %s\n' "$KUBE_CONTEXT" >&2
    exit 1
  }

  printf 'Using Kubernetes context: %s\n' "$KUBE_CONTEXT"
  kubectl kustomize "$CLUSTER_DIR" >/dev/null
  configure_helm_repositories

  kubectl --context "$KUBE_CONTEXT" apply -k "$CLUSTER_DIR/manifests/namespaces"

  install_chart metallb metallb/metallb metallb-system 0.16.1 \
    "$CLUSTER_DIR/helm/metallb/values.yaml"
  wait_for_rollout deployment/metallb-controller metallb-system
  wait_for_rollout daemonset/metallb-speaker metallb-system
  kubectl --context "$KUBE_CONTEXT" apply -k "$CLUSTER_DIR/manifests/metallb"

  install_chart nvidia-device-plugin nvidia-device-plugin/nvidia-device-plugin \
    nvidia-device-plugin 0.20.0 \
    "$CLUSTER_DIR/helm/nvidia-device-plugin/values.yaml"

  install_chart prometheus prometheus-community/prometheus prometheus \
    29.47.2 "$CLUSTER_DIR/helm/prometheus/values.yaml"
    
  install_chart zot zot/zot zot 0.1.134 "$CLUSTER_DIR/helm/zot/values.yaml"
}

main "$@"
