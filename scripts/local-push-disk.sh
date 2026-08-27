#!/usr/bin/env bash
# ============================================================
#  Package the local qcow2 as a KubeVirt containerDisk image
#  and push it to Quay so CDI can import it into OpenShift.
#
#  KubeVirt containerDisk format:
#    FROM scratch
#    COPY disk.qcow2 /disk/disk.qcow2
#
#  CDI's registry importer knows how to extract /disk/* from
#  such an image — this avoids the imagemode OCI limitation.
#
#  Usage:
#    IMAGE=quay.io/waba/bootc-guide:prod ./scripts/local-push-disk.sh
#    (DISK_IMAGE defaults to IMAGE with :disk suffix replaced on the tag)
#
#  Prerequisites:
#    - output/qcow2/disk.qcow2 must exist (run local-qcow2.sh first)
#    - podman must be logged in to quay.io
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-quay.io/waba/bootc-guide:prod}"
# Derive the disk image tag: replace the tag suffix with -disk
# e.g. quay.io/waba/bootc-guide:prod  →  quay.io/waba/bootc-guide:prod-disk
BASE="${IMAGE%:*}"
TAG="${IMAGE##*:}"
DISK_IMAGE="${DISK_IMAGE:-${BASE}:${TAG}-disk}"

QCOW2="${REPO_ROOT}/output/qcow2/disk.qcow2"
# If the amd64 version exists, use that instead
if [[ -f "${REPO_ROOT}/output/qcow2/disk-amd.qcow2" ]]; then
  QCOW2="${REPO_ROOT}/output/qcow2/disk-amd.qcow2"
fi

echo ""
echo "  SOURCE qcow2 : ${QCOW2}"
echo "  DISK_IMAGE   : ${DISK_IMAGE}"
echo ""

if [[ ! -f "${QCOW2}" ]]; then
  echo "  ERROR: ${QCOW2} not found." >&2
  echo "  Run ./scripts/local-qcow2.sh first to build the qcow2." >&2
  exit 1
fi

# Build a minimal containerDisk OCI image from scratch
# The Containerfile is written to a temp dir alongside the qcow2
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

cat > "${TMPDIR}/Containerfile" <<'EOF'
FROM scratch
COPY disk.qcow2 /disk/disk.qcow2
EOF

echo "  Building containerDisk image..."
# Use --platform linux/amd64 — the disk is architecture-independent content
# but CDI on x86 OpenShift expects an amd64-compatible image manifest
podman build -q \
  --platform linux/amd64 \
  -f "${TMPDIR}/Containerfile" \
  -t "${DISK_IMAGE}" \
  "${REPO_ROOT}/output/qcow2"

echo ""
echo "  Pushing ${DISK_IMAGE} to Quay..."
podman push "${DISK_IMAGE}"

echo ""
echo "  Done! Use this in Ansible / demo-run.sh:"
echo "    DISK_IMAGE=${DISK_IMAGE}"
echo ""
