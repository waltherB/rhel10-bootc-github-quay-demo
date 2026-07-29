#!/usr/bin/env bash
# ============================================================
#  Build the ARM64 qcow2 disk image locally, natively, via
#  bootc-image-builder — mirrors what build-qcow2.yml does for
#  AMD64 on GitHub Actions, but runs on-Mac with no emulation
#  since the Mac and the source image are both arm64.
#
#  Used for the local UTM VM, NOT for OpenShift Virtualization
#  (that always uses the AMD64 disk built by GitHub Actions).
#
#  Usage:
#    ./scripts/local-build-qcow2.sh
#    IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64 \
#    DISK_IMAGE_ARM=quay.io/waba/bootc-guide:dev-disk-arm64 \
#      ./scripts/local-build-qcow2.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

IMAGE_ARM="${IMAGE_ARM:-quay.io/waba/bootc-guide:dev-arm64}"
DISK_IMAGE_ARM="${DISK_IMAGE_ARM:-quay.io/waba/bootc-guide:dev-disk-arm64}"
PLATFORM="${TARGET_PLATFORM_LOCAL:-linux/arm64}"

echo ""
echo "  SOURCE IMAGE : ${IMAGE_ARM}"
echo "  OUTPUT DISK  : ${DISK_IMAGE_ARM}"
echo "  PLATFORM     : ${PLATFORM}"
echo ""

podman login registry.redhat.io
podman login quay.io

mkdir -p output

# Native arm64 run — no --platform emulation, same host arch as bootc-image-builder
podman run --rm --privileged \
  --platform "${PLATFORM}" \
  -v "$(pwd)/config/config.toml:/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --config /config.toml \
  "${IMAGE_ARM}"

# Fix ownership (podman run --privileged writes as root on rootful setups)
if [[ "$(id -u)" -ne 0 ]] && command -v sudo &>/dev/null; then
  sudo chown -R "$(id -u):$(id -g)" output 2>/dev/null || true
fi

mv -f output/qcow2/disk.qcow2 output/qcow2/disk-arm.qcow2

# Wrap it as a scratch containerDisk image, same convention as the AMD64 side
mkdir -p ctxdir
cp output/qcow2/disk-arm.qcow2 ctxdir/
cat > ctxdir/Containerfile <<'EOF'
FROM scratch
COPY disk-arm.qcow2 /disk/disk.qcow2
EOF

podman build \
  --platform "${PLATFORM}" \
  --no-cache \
  -f ctxdir/Containerfile \
  -t "${DISK_IMAGE_ARM}" \
  ctxdir

podman push "${DISK_IMAGE_ARM}"

echo ""
echo "  Pushed ${DISK_IMAGE_ARM}"
echo ""
