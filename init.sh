#!/usr/bin/env bash
set -euo pipefail

# Prepare this workstation to manage the homelab.
# This installs local tools, creates local key material, and installs the SSH
# public key on the configured server using existing SSH access.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly SSH_KEY_FILE="${HOME}/.ssh/ansible"
readonly SOPS_KEY_FILE="${HOME}/.sops/age.agekey"
readonly SOPS_CONFIG="${ROOT_DIR}/.sops.yaml"
readonly MISE_CONFIG="${ROOT_DIR}/mise.toml"
readonly SSH_TARGET="${SSH_TARGET:-ansible@homelab}"
readonly FLUX_NAMESPACE="flux-system"
readonly SOPS_SECRET_NAME="sops-age"
readonly KUBECONFIG_DIR="${HOME}/.kube/tinycloud"
readonly KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"
readonly KUBERNETES_SERVER="${KUBERNETES_SERVER:-https://tinycloud:6443}"

readonly SSH_CONNECT_OPTIONS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
TEMP_PATHS=()

cleanup() {
  [[ "${#TEMP_PATHS[@]}" -gt 0 ]] && rm -rf "${TEMP_PATHS[@]}"
  return 0
}

trap cleanup EXIT

run_mise() {
  mise exec -- "$@"
}
fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./init.sh <command>

Commands:
  check      Verify local and cluster state without changing anything.
  bootstrap  Install tools and converge workstation/cluster access.
EOF
}

ensure_formula() {
  local formula="$1"

  if ! brew list --formula "$formula" >/dev/null 2>&1; then
    printf 'Installing %s...\n' "$formula"
    NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew install "$formula"
  fi
}

ensure_mise() {
  ensure_formula mise
  command -v mise >/dev/null 2>&1 || fail "mise is required after installing it"
  [[ -f "$MISE_CONFIG" ]] || fail "missing mise configuration: $MISE_CONFIG"
}

ensure_installed() {
  local description="$1"
  local check_cmd="$2"
  shift 2
  local install_cmd=("$@")

  if ! eval "$check_cmd" >/dev/null 2>&1; then
    printf 'Installing %s...\n' "$description"
    local log_file
    log_file="$(mktemp)"
    TEMP_PATHS+=("$log_file")
    if ! "${install_cmd[@]}" >"$log_file" 2>&1; then
      cat "$log_file" >&2
      fail "could not install $description"
    fi
  fi
}

install_project_tools() {
  printf 'Installing project tools...\n'
  local log_file
  log_file="$(mktemp)"
  TEMP_PATHS+=("$log_file")
  if ! mise install >"$log_file" 2>&1; then
    cat "$log_file" >&2
    fail "could not install project tools from $MISE_CONFIG"
  fi

  ensure_installed "ansible-lint" "command -v ansible-lint" \
    pipx install ansible-lint

  ensure_installed "Ansible collections" \
    "test -d ${ROOT_DIR}/machines/collections/ansible_collections/ansible/posix" \
    ansible-galaxy collection install ansible.posix \
      -p "${ROOT_DIR}/machines/collections"
}

assert_regular_file_or_absent() {
  local file="$1"

  [[ ! -e "$file" || -f "$file" ]] || fail "$file exists but is not a regular file"
}

ensure_parent_dir() {
  local dir
  dir="$(dirname -- "$1")"
  mkdir -p "$dir"
  chmod 700 "$dir"
}

ensure_ssh_keypair() {
  assert_regular_file_or_absent "$SSH_KEY_FILE"
  ensure_parent_dir "$SSH_KEY_FILE"

  if [[ ! -e "$SSH_KEY_FILE" ]]; then
    ssh-keygen -q -t ed25519 -f "$SSH_KEY_FILE" -N '' \
      -C "homelab-ansible@$(hostname -s)"
    printf 'Generated SSH key: %s\n' "$SSH_KEY_FILE"
  fi

  chmod 600 "$SSH_KEY_FILE"

  if [[ ! -f "${SSH_KEY_FILE}.pub" ]]; then
    local public_key_tmp
    public_key_tmp="$(mktemp "${SSH_KEY_FILE}.pub.XXXXXX")"
    TEMP_PATHS+=("$public_key_tmp")
    ssh-keygen -q -y -f "$SSH_KEY_FILE" > "$public_key_tmp"
    chmod 644 "$public_key_tmp"
    mv "$public_key_tmp" "${SSH_KEY_FILE}.pub"
    printf 'Recreated SSH public key: %s.pub\n' "$SSH_KEY_FILE"
  else
    chmod 644 "${SSH_KEY_FILE}.pub"
  fi
}

ensure_age_key() {
  assert_regular_file_or_absent "$SOPS_KEY_FILE"
  ensure_parent_dir "$SOPS_KEY_FILE"

  if [[ ! -e "$SOPS_KEY_FILE" ]]; then
    local key_tmp_dir
    local key_tmp
    key_tmp_dir="$(mktemp -d "${SOPS_KEY_FILE}.XXXXXX")"
    TEMP_PATHS+=("$key_tmp_dir")
    key_tmp="${key_tmp_dir}/age.agekey"
    if ! run_mise age-keygen -o "$key_tmp" >/dev/null; then
      fail "could not generate the age key"
    fi
    chmod 600 "$key_tmp"
    mv "$key_tmp" "$SOPS_KEY_FILE"
    printf 'Generated age key: %s\n' "$SOPS_KEY_FILE"
  fi

  chmod 600 "$SOPS_KEY_FILE"
}

validate_sops_recipient() {
  local configured_recipient
  local derived_recipient

  [[ -f "$SOPS_CONFIG" ]] || fail "missing SOPS configuration: $SOPS_CONFIG"
  configured_recipient="$(awk '/^[[:space:]]*age:/ { print $2; exit }' "$SOPS_CONFIG")"
  [[ -n "$configured_recipient" ]] || fail "no age recipient configured in $SOPS_CONFIG"

  derived_recipient="$(run_mise age-keygen -y "$SOPS_KEY_FILE")"
  [[ "$derived_recipient" == "$configured_recipient" ]] || \
    fail "local age key does not match the recipient in $SOPS_CONFIG"
}

install_ssh_public_key() {
  command -v ssh >/dev/null 2>&1 || fail "ssh is required for server bootstrap"

  printf 'Configuring SSH access on %s...\n' "$SSH_TARGET"
  ssh "${SSH_CONNECT_OPTIONS[@]}" "$SSH_TARGET" '
    umask 077
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    chmod 700 "$HOME/.ssh"
    IFS= read -r key
    if ! grep -Fqx -- "$key" "$HOME/.ssh/authorized_keys"; then
      printf "%s\n" "$key" >> "$HOME/.ssh/authorized_keys"
    fi
    chmod 600 "$HOME/.ssh/authorized_keys"
  ' < "${SSH_KEY_FILE}.pub" || fail "could not install the SSH key on $SSH_TARGET"

  ssh "${SSH_CONNECT_OPTIONS[@]}" -o IdentitiesOnly=yes -i "$SSH_KEY_FILE" \
    "$SSH_TARGET" true || fail "the generated SSH key could not authenticate to $SSH_TARGET"
  printf 'SSH access verified.\n'
}

ensure_kubeconfig() {
  local kubeconfig_tmp
  local updated_tmp

  ensure_parent_dir "$KUBECONFIG_FILE"

  if [[ ! -e "$KUBECONFIG_FILE" ]]; then
    kubeconfig_tmp="$(mktemp "${KUBECONFIG_FILE}.XXXXXX")"
    TEMP_PATHS+=("$kubeconfig_tmp")
    if ! ssh "${SSH_CONNECT_OPTIONS[@]}" "$SSH_TARGET" \
      'sudo -n cat /etc/rancher/k3s/k3s.yaml' > "$kubeconfig_tmp"; then
      fail "could not fetch the K3s kubeconfig from $SSH_TARGET; passwordless sudo is required"
    fi

    updated_tmp="$(mktemp "${KUBECONFIG_FILE}.XXXXXX")"
    TEMP_PATHS+=("$updated_tmp")
    sed -E "s|^([[:space:]]*server: ).*|\\1${KUBERNETES_SERVER}|" \
      "$kubeconfig_tmp" > "$updated_tmp"
    chmod 600 "$updated_tmp"
    mv "$updated_tmp" "$KUBECONFIG_FILE"
    printf 'Fetched kubeconfig: %s\n' "$KUBECONFIG_FILE"
  fi

  chmod 600 "$KUBECONFIG_FILE"
  KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl get nodes >/dev/null \
    || fail "could not connect to the cluster using $KUBECONFIG_FILE"
  printf 'Kubernetes access verified: %s\n' "$KUBERNETES_SERVER"
}

reconcile_flux_sops_secret() {
  if ! KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl -n "$FLUX_NAMESPACE" \
    get namespace "$FLUX_NAMESPACE" >/dev/null 2>&1; then
    printf 'Flux is not installed; skipping the SOPS Secret.\n'
    return 0
  fi

  printf 'Reconciling Flux SOPS Secret...\n'
  KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl -n "$FLUX_NAMESPACE" \
    create secret generic "$SOPS_SECRET_NAME" \
    --from-file=age.agekey="$SOPS_KEY_FILE" \
    --dry-run=client -o yaml |
    KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl apply -f -
  printf 'Flux SOPS Secret ready.\n'
}
check_project_tools() {
  local tool

  for tool in age-keygen sops kubectl ansible; do
    run_mise command -v "$tool" >/dev/null 2>&1 \
      || fail "mise-managed tool is not installed: $tool"
  done

  command -v ansible-lint >/dev/null 2>&1 \
    || fail "ansible-lint is not installed: pipx install ansible-lint"
}

check_ssh_keypair() {
  [[ -f "$SSH_KEY_FILE" ]] || fail "missing SSH private key: $SSH_KEY_FILE"
  [[ -f "${SSH_KEY_FILE}.pub" ]] || fail "missing SSH public key: ${SSH_KEY_FILE}.pub"
  ssh-keygen -q -y -f "$SSH_KEY_FILE" >/dev/null \
    || fail "invalid SSH private key: $SSH_KEY_FILE"
}

check_age_key() {
  [[ -f "$SOPS_KEY_FILE" ]] || fail "missing age key: $SOPS_KEY_FILE"
  run_mise age-keygen -y "$SOPS_KEY_FILE" >/dev/null \
    || fail "invalid age key: $SOPS_KEY_FILE"
  validate_sops_recipient
}

check_kubeconfig() {
  [[ -f "$KUBECONFIG_FILE" ]] || fail "missing kubeconfig: $KUBECONFIG_FILE"
  KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl get nodes >/dev/null \
    || fail "could not connect to the cluster using $KUBECONFIG_FILE"
}

check_remote_access() {
  ssh "${SSH_CONNECT_OPTIONS[@]}" -o IdentitiesOnly=yes -i "$SSH_KEY_FILE" \
    "$SSH_TARGET" true >/dev/null \
    || fail "generated SSH key could not authenticate to $SSH_TARGET"
}

check_flux_state() {
  if ! KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl -n "$FLUX_NAMESPACE" \
    get namespace "$FLUX_NAMESPACE" >/dev/null 2>&1; then
    return 2
  fi

  if ! KUBECONFIG="$KUBECONFIG_FILE" run_mise kubectl -n "$FLUX_NAMESPACE" \
    get secret "$SOPS_SECRET_NAME" >/dev/null 2>&1; then
    return 1
  fi
}

check_workstation() {
  command -v brew >/dev/null 2>&1 || fail "Homebrew is required; install it from https://brew.sh/"
  command -v mise >/dev/null 2>&1 || fail "mise is required; run ./init.sh bootstrap"
  [[ -f "$MISE_CONFIG" ]] || fail "missing mise configuration: $MISE_CONFIG"
  check_project_tools
  check_ssh_keypair
  check_age_key
  check_remote_access
  check_kubeconfig

  if check_flux_state 2>/dev/null; then
    printf 'Checks passed: local tools, keys, SSH, Kubernetes, and Flux state.\n'
  else
    printf 'Checks passed: local tools, keys, SSH, and Kubernetes.\n'
    printf 'Warning: Flux is not installed; SOPS Secret check was skipped.\n'
  fi
}
confirm_bootstrap() {
  if [[ "${1:-}" == "--yes" ]]; then
    [[ "$#" -eq 1 ]] || fail "bootstrap --yes does not accept additional arguments"
    return 0
  fi
  [[ "$#" -eq 0 ]] || fail "unknown bootstrap argument: $1"
  [[ -t 0 ]] || fail "bootstrap requires confirmation; rerun with --yes"

  printf 'Bootstrap will modify local files, remote SSH access, and cluster state. Continue? [y/N] '
  local response
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] || fail "bootstrap cancelled"
}

bootstrap_workstation() {
  umask 077
  ensure_mise
  install_project_tools
  ensure_ssh_keypair
  ensure_age_key
  install_ssh_public_key
  ensure_kubeconfig
  validate_sops_recipient
  reconcile_flux_sops_secret
  print_summary
}
print_summary() {
  printf '\nBootstrap complete.\n'
  printf 'SSH key: %s\n' "$SSH_KEY_FILE"
  printf 'Kubeconfig: %s\n' "$KUBECONFIG_FILE"
  printf 'Next: mise run check\n'
}

main() {
  case "${1:-}" in
    check)
      [[ "$#" -eq 1 ]] || fail "check does not accept arguments"
      check_workstation
      ;;
    bootstrap)
      shift
      confirm_bootstrap "$@"
      bootstrap_workstation
      ;;
    help)
      usage
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

