#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

# IMAGE_ARM is the local (Mac, arm64) bootc image; the amd64 image is
# built and pushed by GitHub Actions, never from here.
IMAGE_ARM="${IMAGE_ARM:-quay.io/waba/bootc-guide:dev-arm64}"

podman login quay.io
podman push "$IMAGE_ARM"
