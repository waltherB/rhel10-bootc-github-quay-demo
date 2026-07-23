#!/bin/bash
set -euo pipefail

# Source env file if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"
PLATFORM="${TARGET_PLATFORM:-linux/amd64,linux/arm64}"
#PLATFORM="${TARGET_PLATFORM:-linux/arm64}"
VM_SSH_KEY="${VM_SSH_KEY:-id_ed25519}"  # Default key name

# Login to registry.redhat.io
podman login registry.redhat.io

# Build with proper SSH key path
podman build \
  --platform "$PLATFORM" \
  --build-arg RHSM_ACTIVATION_KEY="${RHSM_ACTIVATION_KEY:-}" \
  --build-arg DEMO_PUB_KEY="$(cat ~/.ssh/${VM_SSH_KEY}.pub 2>/dev/null || echo '')" \
  --build-arg RHSM_ORG="${RHSM_ORG:-}" \
  -t "$IMAGE" \
  .
