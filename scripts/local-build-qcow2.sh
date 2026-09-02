#!/usr/bin/env bash
# ============================================================
#  Build the ARM64 qcow2 disk image locally, natively, via
#  bootc-image-builder — mirrors what build-sign-push.yml does for
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
# Preserve explicit command-line environment overrides while loading defaults.
IMAGE_ARM_OVERRIDE="${IMAGE_ARM-}"
IMAGE_ARM_WAS_SET="${IMAGE_ARM+x}"
DISK_IMAGE_ARM_OVERRIDE="${DISK_IMAGE_ARM-}"
DISK_IMAGE_ARM_WAS_SET="${DISK_IMAGE_ARM+x}"
PLATFORM_OVERRIDE="${TARGET_PLATFORM_LOCAL-}"
PLATFORM_WAS_SET="${TARGET_PLATFORM_LOCAL+x}"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

if [[ -n "${IMAGE_ARM_WAS_SET}" ]]; then IMAGE_ARM="${IMAGE_ARM_OVERRIDE}"; fi
if [[ -n "${DISK_IMAGE_ARM_WAS_SET}" ]]; then DISK_IMAGE_ARM="${DISK_IMAGE_ARM_OVERRIDE}"; fi
if [[ -n "${PLATFORM_WAS_SET}" ]]; then TARGET_PLATFORM_LOCAL="${PLATFORM_OVERRIDE}"; fi

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

# IMAGE_ARM was built LOCALLY in step 2 and has NOT been pushed to Quay yet
# (that happens later, in step 4) — so we must use what's already sitting in
# local podman storage, not pull it from the registry (that tag doesn't
# exist remotely yet and will 404 with "manifest unknown").
if ! podman image exists "${IMAGE_ARM}"; then
  echo "  ERROR: ${IMAGE_ARM} not found in local podman storage." >&2
  echo "  Run step 2 (local build) first: ./scripts/local-build.sh" >&2
  exit 1
fi

# bootc-image-builder itself comes from a registry. Reuse the local copy only
# when it has the same architecture as the local UTM build.
BUILDER_ARCH="${PLATFORM#*/}"
if [[ "$(podman image inspect registry.redhat.io/rhel10/bootc-image-builder:latest \
  --format '{{.Architecture}}' 2>/dev/null || true)" != "${BUILDER_ARCH}" ]]; then
  podman pull --platform "${PLATFORM}" registry.redhat.io/rhel10/bootc-image-builder:latest
fi

mkdir -p output

# ── Preflight: bootc-image-builder requires a ROOTFUL Podman Machine ──
# Per upstream docs and Red Hat's own guidance, bootc-image-builder simply
# does not work against a rootless Podman Machine on macOS. If the machine
# was ever switched between rootless/rootful, its lock file can also end up
# stale, which surfaces as a cryptic Go panic ("failed to open N locks in
# /libpod_lock: numerical result out of range") rather than a clear error —
# so we check and fail fast with the actual fix instead.
if [[ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" == "true" ]]; then
  echo "  ERROR: your Podman Machine is running ROOTLESS." >&2
  echo "  bootc-image-builder requires rootful. Fix with:" >&2
  echo "    podman machine stop" >&2
  echo "    podman machine set --rootful" >&2
  echo "    podman machine start" >&2
  exit 1
fi

# ── Discover the real container storage GraphRoot ──────────────
# bootc-image-builder needs to see the same image layer data the outer
# `podman pull`/`podman build` above wrote — that lives under GraphRoot.
# Unlike the GitHub Actions runner (rootful, fixed at
# /var/lib/containers/storage), your storage root here is whatever
# `podman info` reports for THIS install (rootful or rootless).
GRAPHROOT="$(podman info --format '{{.Store.GraphRoot}}')"

if [[ -z "${GRAPHROOT}" ]]; then
  echo "  ERROR: could not determine podman storage GraphRoot via 'podman info'." >&2
  exit 1
fi

echo "  GraphRoot: ${GRAPHROOT}"

# Deliberately do NOT also bind-mount RunRoot (e.g. /run/containers/storage).
# RunRoot only holds ephemeral lock/state files, not image data, and sharing
# it across two different containers/storage versions (host Podman vs. the
# one baked into the bootc-image-builder image) causes a lock-file-size
# mismatch: "failed to open N locks in /libpod_lock: numerical result out
# of range". bootc-image-builder happily initializes its own throwaway
# RunRoot inside the container while reading image data from the shared
# GraphRoot — this matches Red Hat's own documented invocation, which only
# ever mounts GraphRoot.
#
# Native run on the same arch as the image — no --platform needed here.
# If this still fails with "failed to open N locks in /libpod_lock:
# numerical result out of range", Podman's lock manager keeps its lock
# file under /dev/shm (NOT under GraphRoot/RunRoot) — sharing that too
# keeps the inner container's view of locks consistent with the host's.
# As a last, non-destructive resort: podman system renumber
podman run --rm --privileged \
  --platform "${PLATFORM}" \
  --pull=never \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/config/config.toml:/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v "${GRAPHROOT}:${GRAPHROOT}" \
  -v /dev/shm:/dev/shm \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --config /config.toml \
  "${IMAGE_ARM}"

# Only fix ownership under ./output if needed
if [[ "$(id -u)" -ne 0 ]]; then
  if find output ! -user "$(id -u)" -print -quit 2>/dev/null | grep -q .; then
    sudo chown -R "$(id -u):$(id -g)" output
  fi
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
  -f ctxdir/Containerfile \
  -t "${DISK_IMAGE_ARM}" \
  ctxdir

podman push "${DISK_IMAGE_ARM}"

echo ""
echo "  Pushed ${DISK_IMAGE_ARM}"
echo ""
