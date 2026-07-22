#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"

# On macOS for bootc-image-builder, ensure podman machine is rootful:
# podman machine stop
# podman machine set --rootful
# podman machine start

podman pull registry.redhat.io/rhel10/bootc-image-builder:latest
mkdir -p output

podman run --rm --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ./config/config.toml:/config.toml:ro \
  -v ./output:/output \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --config /config.toml \
  "$IMAGE"
