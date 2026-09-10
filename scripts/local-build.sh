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
if [[ "$VM_SSH_KEY" != /* ]]; then
  VM_SSH_KEY="${HOME}/.ssh/${VM_SSH_KEY}"
fi

if [[ ! -r "${VM_SSH_KEY}.pub" ]]; then
  echo "ERROR: SSH public key not found: ${VM_SSH_KEY}.pub" >&2
  exit 1
fi
DEMO_PUB_KEY="$(<"${VM_SSH_KEY}.pub")"
if [[ -z "$DEMO_PUB_KEY" ]]; then
  echo "ERROR: SSH public key is empty: ${VM_SSH_KEY}.pub" >&2
  exit 1
fi

# Login to registry.redhat.io
podman login registry.redhat.io

# Native single-arch build — no --platform emulation needed on Apple Silicon
podman build -q \
  --platform "$PLATFORM" \
  --build-arg RHSM_ACTIVATION_KEY="${RHSM_ACTIVATION_KEY:-}" \
  --build-arg DEMO_PUB_KEY="$DEMO_PUB_KEY" \
  --build-arg RHSM_ORG="${RHSM_ORG:-}" \
  -t "$IMAGE_ARM" \
  .
