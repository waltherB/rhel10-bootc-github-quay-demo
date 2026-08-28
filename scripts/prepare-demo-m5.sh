#!/usr/bin/env bash
set -euo pipefail

# Prepare the four ARM64 images used by demo-run-m5.sh.
# The RHEL/package build happens once; the remaining images reuse its layers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${SOURCE_IMAGE_ARM:=${IMAGE_ARM:-${QUAY_REPO}:dev-arm64}}"
: "${PUSH_IMAGES:=1}"
: "${REBUILD_GOOD:=1}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

build_child() {
  local image="$1"
  local context="$2"
  podman build --platform linux/arm64 -t "${image}" "${context}"
}

require_command podman

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: run this preparation script on an ARM64 Mac, not ${HOSTTYPE:-unknown}." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ "${REBUILD_GOOD}" == "1" ]] || ! podman image exists "${IMAGE_GOOD}"; then
  echo "==> Building ${IMAGE_GOOD} from the repository Containerfile"
  (cd "${REPO_DIR}" && ./scripts/local-build.sh)
  if ! podman image exists "${SOURCE_IMAGE_ARM}"; then
    echo "ERROR: expected local baseline image was not built: ${SOURCE_IMAGE_ARM}" >&2
    exit 1
  fi
  # local-build.sh sources demo-env.sh, so preserve its configured source tag
  # and create the lifecycle tag used by this scenario explicitly.
  podman tag "${SOURCE_IMAGE_ARM}" "${IMAGE_GOOD}"
else
  echo "==> Reusing existing ${IMAGE_GOOD}"
fi

mkdir -p "${TMP_DIR}/update" "${TMP_DIR}/broken" "${TMP_DIR}/fixed"

cat > "${TMP_DIR}/update/Containerfile" <<EOF
FROM ${IMAGE_GOOD}
COPY index.html /var/www/html/index.html
LABEL org.opencontainers.image.title="RHEL Image Mode demo v2"
EOF

cat > "${TMP_DIR}/update/index.html" <<'EOF'
<!doctype html>
<html lang="da">
<head><meta charset="utf-8"><title>RHEL Image Mode - v2</title></head>
<body style="font-family: sans-serif; margin: 2rem;">
<h1>RHEL Image Mode Demo - version 2</h1>
<p>Denne side kommer fra en ny bootc image deployment.</p>
<p><strong>Status:</strong> Opdateret uden manuel ændring på VM'en.</p>
</body>
</html>
EOF

cat > "${TMP_DIR}/broken/Containerfile" <<EOF
FROM ${IMAGE_UPDATE}
RUN rm -f /etc/systemd/system/multi-user.target.wants/httpd.service
LABEL org.opencontainers.image.title="RHEL Image Mode demo broken"
EOF

cat > "${TMP_DIR}/fixed/Containerfile" <<EOF
FROM ${IMAGE_UPDATE}
RUN systemctl enable httpd
COPY index.html /var/www/html/index.html
LABEL org.opencontainers.image.title="RHEL Image Mode demo v3 fixed"
EOF

cat > "${TMP_DIR}/fixed/index.html" <<'EOF'
<!doctype html>
<html lang="da">
<head><meta charset="utf-8"><title>RHEL Image Mode - v3</title></head>
<body style="font-family: sans-serif; margin: 2rem;">
<h1>RHEL Image Mode Demo - version 3</h1>
<p>Fejlen er rettet i den nye image-version.</p>
<p><strong>Status:</strong> HTTPD kører igen efter rollback og redeploy.</p>
</body>
</html>
EOF

echo "==> Building lightweight child-images"
build_child "${IMAGE_UPDATE}" "${TMP_DIR}/update"
build_child "${IMAGE_BROKEN}" "${TMP_DIR}/broken"
build_child "${IMAGE_FIXED}" "${TMP_DIR}/fixed"

if [[ "${PUSH_IMAGES}" == "1" ]]; then
  echo "==> Pushing demo images to Quay"
  podman push "${IMAGE_GOOD}"
  podman push "${IMAGE_UPDATE}"
  podman push "${IMAGE_BROKEN}"
  podman push "${IMAGE_FIXED}"
fi

echo
echo "Prepared images:"
printf '  %s\n' "${IMAGE_GOOD}" "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}"
echo
echo "Next: create or refresh the UTM ARM64 VM disk from ${IMAGE_GOOD}."
