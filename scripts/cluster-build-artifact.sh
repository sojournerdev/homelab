#!/usr/bin/env bash
set -euo pipefail

artifact_dir=".cache/cluster-artifact"

rm -rf -- "$artifact_dir"
mkdir -p "$artifact_dir"

cp -R clusters/tinycloud/. "$artifact_dir"
