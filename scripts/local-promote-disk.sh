#!/usr/bin/env bash
# ============================================================
#  Promote containerDisk image: :dev-disk → :prod-disk
#  (same qcow2 content, new tag — no rebuild required)
#
#  Mirrors the OS image promote: :dev → :prod
#
#  Usage:
#    IMAGE=quay.io/waba/bootc-guide:prod ./scripts/local-promote-disk.sh
#    # promotes :dev-disk → :prod-disk automatically
#
#    Or override explicitly:
#    SOURCE_DISK=quay.io/waba/bootc-guide:dev-disk \
#    TARGET_DISK=quay.io/waba/bootc-guide:prod-disk \
#      ./scripts/local-promote-disk.sh
# ============================================================
set -euo pipefail

IMAGE="${IMAGE:-quay.io/waba/bootc-guide:prod}"
_BASE="${IMAGE%:*}"
_TAG="${IMAGE##*:}"

# Default: promote from dev-disk to <tag>-disk
SOURCE_DISK="${SOURCE_DISK:-${_BASE}:dev-disk}"
TARGET_DISK="${TARGET_DISK:-${_BASE}:${_TAG}-disk}"

echo ""
echo "  SOURCE: ${SOURCE_DISK}"
echo "  TARGET: ${TARGET_DISK}"
echo ""

if ! command -v skopeo &>/dev/null; then
  echo "  ERROR: skopeo is required. Install with: brew install skopeo" >&2
  exit 1
fi

skopeo copy \
  "docker://${SOURCE_DISK}" \
  "docker://${TARGET_DISK}"

echo ""
echo "  Promoted ${SOURCE_DISK} → ${TARGET_DISK}"
echo ""
