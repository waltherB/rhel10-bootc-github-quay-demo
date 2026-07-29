#!/bin/bash
# ============================================================
#  Build the bootc container image locally (native ARM64 on Mac).
#  The AMD64 bootc image is built by GitHub Actions CI instead —
#  never cross-build amd64 here, it just fights Podman's QEMU
#  emulation layer on Apple Silicon for no benefit.
#
#  Usage:
#    ./scripts/local-build.sh
#    IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-build.sh
# ============================================================
set -euo pipefail

# Source env file if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

IMAGE_ARM="${IMAGE_ARM:-quay.io/waba/bootc-guide:dev-arm64}"
PLATFORM="${TARGET_PLATFORM_LOCAL:-linux/arm64}"
VM_SSH_KEY="${VM_SSH_KEY:-id_ed25519}"  # Default key name

# Login to registry.redhat.io
podman login registry.redhat.io

# Native single-arch build — no --platform emulation needed on Apple Silicon
podman build -q \
  --platform "$PLATFORM" \
  --build-arg RHSM_ACTIVATION_KEY="${RHSM_ACTIVATION_KEY:-}" \
  --build-arg DEMO_PUB_KEY="$(cat ~/.ssh/${VM_SSH_KEY}.pub 2>/dev/null || echo '')" \
  --build-arg RHSM_ORG="${RHSM_ORG:-}" \
  -t "$IMAGE_ARM" \
  .
