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

# Make sure the source image is actually present in local storage before we
# ask bootc-image-builder to read it — it does NOT re-pull on its own if the
# mount below doesn't line up with where it actually lives.
podman pull "${IMAGE_ARM}"
podman pull registry.redhat.io/rhel10/bootc-image-builder:latest

mkdir -p output

# ── Discover the real container storage paths ─────────────────
# bootc-image-builder needs to see the same containers/storage the outer
# `podman pull` above just wrote to, via bind mount. Unlike the GitHub
# Actions runner (rootful, fixed at /var/lib/containers/storage), Podman on
# Mac normally runs ROOTLESS inside the Podman Machine VM, and its storage
# root lives at whatever `podman info` reports — typically something like
# ~/.local/share/containers/storage inside that VM, NOT /var/lib/....
# Hardcoding the rootful CI path here is exactly what produced:
#   "could not access container storage ... did you forget -v ...?"
GRAPHROOT="$(podman info --format '{{.Store.GraphRoot}}')"
RUNROOT="$(podman info --format '{{.Store.RunRoot}}')"

if [[ -z "${GRAPHROOT}" || -z "${RUNROOT}" ]]; then
  echo "  ERROR: could not determine podman storage paths via 'podman info'." >&2
  exit 1
fi

note_storage() { echo "  $1: $2"; }
note_storage "GraphRoot" "${GRAPHROOT}"
note_storage "RunRoot"   "${RUNROOT}"

# Native arm64 run — no --platform emulation, same host arch as bootc-image-builder
podman run --rm --privileged \
  --platform "${PLATFORM}" \
  -v "$(pwd)/config/config.toml:/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v "${GRAPHROOT}:${GRAPHROOT}" \
  -v "${RUNROOT}:${RUNROOT}" \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --config /config.toml \
  "${IMAGE_ARM}"

# Fix ownership if anything came back root-owned (only matters on rootful
# setups; on the normal rootless Mac path this is usually a no-op).
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

podman build -q \
  --platform "${PLATFORM}" \
  --no-cache \
  -f ctxdir/Containerfile \
  -t "${DISK_IMAGE_ARM}" \
  ctxdir

podman push "${DISK_IMAGE_ARM}"

echo ""
echo "  Pushed ${DISK_IMAGE_ARM}"
echo ""