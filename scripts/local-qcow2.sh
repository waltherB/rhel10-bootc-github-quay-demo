#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"
# Default to amd64 for cross-architecture builds from arm64 Mac
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

# The KubeVirt/SNO target is x86_64 only. Building anything else here would
# silently produce a disk that boots nowhere useful (and won't get renamed
# to disk-amd.qcow2 below, masking the mistake). Refuse instead of guessing.
if [[ "$TARGET_PLATFORM" != "linux/amd64" ]]; then
  echo "❌ TARGET_PLATFORM=$TARGET_PLATFORM, but this demo's VM/KubeVirt target is amd64 only." >&2
  echo "   Unset TARGET_PLATFORM (or set it to linux/amd64) and re-run." >&2
  exit 1
fi

# Determine output filename based on architecture
if [[ "$TARGET_PLATFORM" == "linux/amd64" ]]; then
  OUTPUT_FILE="disk-amd.qcow2"
else
  OUTPUT_FILE="disk.qcow2"
fi

# On macOS for bootc-image-builder, ensure podman machine is rootful:
# podman machine stop
# podman machine set --rootful
# podman machine start

# 1. Pull the source image (required by newer bootc-image-builder)
echo "📥 Pulling source image: $IMAGE"
podman pull "$IMAGE"

# 2. Pull the builder tool
echo "📥 Pulling builder tool..."
podman pull registry.redhat.io/rhel10/bootc-image-builder:latest

mkdir -p output

echo "⚙️  Running bootc-image-builder..."

podman run --rm --privileged \
  --platform "$TARGET_PLATFORM" \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ./config/config.toml:/config.toml:ro \
  -v ./output:/output \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --local \
  --config /config.toml \
  "$IMAGE"


# Rename the output file if we are building for amd64
if [[ "$TARGET_PLATFORM" == "linux/amd64" ]]; then
  if [[ -f "output/qcow2/disk.qcow2" ]]; then
    mv output/qcow2/disk.qcow2 output/qcow2/disk-amd.qcow2
    echo "Renamed to disk-amd.qcow2"
  fi
fi
