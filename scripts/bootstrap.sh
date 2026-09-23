#!/usr/bin/env bash
set -euo pipefail

command -v mise >/dev/null 2>&1 || brew install mise

mise install
mise run workstation-init
