#!/bin/sh
set -eu

if ! command -v mise >/dev/null 2>&1; then
  brew install mise
fi

mise --version
