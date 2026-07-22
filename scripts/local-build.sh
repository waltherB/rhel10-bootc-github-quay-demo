#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"
PLATFORM="${TARGET_PLATFORM:-linux/amd64,linux/arm64}"

podman login registry.redhat.io
podman build \
  --platform "$PLATFORM" \
  --build-arg RHSM_ACTIVATION_KEY="${RHSM_ACTIVATION_KEY:-}" \
  --build-arg DEMO_PUB_KEY="$(cat ~/.ssh/${VM_SSH_KEY}.pub)" \
  --build-arg RHSM_ORG="${RHSM_ORG:-}" \
  -t "$IMAGE" \
  .
