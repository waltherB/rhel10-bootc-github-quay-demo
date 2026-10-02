#!/usr/bin/env bash
set -euo pipefail

# Prepare the four ARM64 images used by demo-run-m5.sh.
#
# DIGEST COHERENCE GUARANTEE
# ───────────────────────────
# All child images are built FROM a digest-pinned reference of the base image
# that was already pushed to Quay — not from a mutable local tag.  This ensures
# the qcow2 disk, demo-v1-arm64, demo-v2-chatbot-arm64, demo-broken-arm64 and
# demo-v3-fixed-arm64 all share exactly the same base layer chain so that
# `bootc switch` succeeds on the VM regardless of what the VM booted from.
#
# Build order:
#   1. Build base image locally
#   2. Push base → capture Quay digest  → BASE_DIGEST
#   3. Build qcow2 disk from BASE_DIGEST (VM initial disk)
#   4. Build update/broken/fixed FROM quay.io/…:demo-v1-arm64@BASE_DIGEST
#   5. Push children → capture their Quay digests
#   6. Verify each pushed child shares the same base layer (first 85 layers)
#   7. Sign all images

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Preserve explicit command-line overrides before sourcing demo-env.sh
BUILD_UTM_DISK_OVERRIDE="${BUILD_UTM_DISK-}"
BUILD_UTM_DISK_WAS_SET="${BUILD_UTM_DISK+x}"
BUILD_OCPVIRT_DISK_OVERRIDE="${BUILD_OCPVIRT_DISK-}"
BUILD_OCPVIRT_DISK_WAS_SET="${BUILD_OCPVIRT_DISK+x}"

if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

if [[ -n "${BUILD_UTM_DISK_WAS_SET}" ]]; then BUILD_UTM_DISK="${BUILD_UTM_DISK_OVERRIDE}"; fi
if [[ -n "${BUILD_OCPVIRT_DISK_WAS_SET}" ]]; then BUILD_OCPVIRT_DISK="${BUILD_OCPVIRT_DISK_OVERRIDE}"; fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-chatbot-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${DISK_IMAGE_GOOD:=${QUAY_REPO}:demo-v1-disk-arm64}"
: "${IMAGE_AMD:=${QUAY_REPO}:dev-amd64}"
: "${DISK_IMAGE_AMD:=${QUAY_REPO}:dev-disk-amd64}"
: "${SOURCE_IMAGE_ARM:=${IMAGE_ARM:-${QUAY_REPO}:dev-arm64}}"
: "${ADD_CHATBOT:=1}"
: "${AI_LAB_RECIPES_DIR:=}"
: "${CHATBOT_PORT:=8501}"
: "${PUSH_IMAGES:=1}"
: "${REBUILD_GOOD:=1}"
: "${BUILD_UTM_DISK:=1}"
: "${BUILD_OCPVIRT_DISK:=1}"
: "${TEST_QEMU:=0}"

# ─────────────────────────────────────────────────────────────────────────────
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

# Push an image and return its Quay digest via the named variable.
# Usage: push_and_capture IMAGE VAR_NAME
push_and_capture() {
  local image="$1"
  local varname="$2"
  echo "==> Pushing ${image}"
  podman push "${image}"
  local digest
  digest="$(podman image inspect --format '{{index .RepoDigests 0}}' "${image}" \
    | sed 's/.*@//')"
  if [[ -z "${digest}" ]]; then
    # RepoDigests may not be populated immediately; fall back to skopeo
    digest="$(skopeo inspect --format '{{.Digest}}' "docker://${image}")"
  fi
  [[ -n "${digest}" ]] || {
    echo "ERROR: could not determine pushed digest for ${image}" >&2
    exit 1
  }
  printf 'INFO: %s pushed → %s\n' "${image}" "${digest}"
  # shellcheck disable=SC2229
  read -r "${varname}" <<< "${digest}"
}

# Build a child image from a digest-pinned FROM, never from a mutable tag.
# Usage: build_child IMAGE CONTEXT_DIR BASE_IMAGE_WITH_DIGEST
build_child() {
  local image="$1"
  local context="$2"
  # The Containerfile in context must already contain the correct FROM line.
  podman build --no-cache --pull=never --platform linux/arm64 -t "${image}" "${context}"
}

assert_bootable_arm64() {
  local image="$1"
  local architecture bootable
  architecture="$(podman image inspect --format '{{.Architecture}}' "${image}")"
  bootable="$(podman image inspect --format '{{index .Config.Labels "ostree.bootable"}}' "${image}")"
  if [[ "${architecture}" != "arm64" || "${bootable}" != "1" ]]; then
    echo "ERROR: ${image} is not a bootable ARM64 image (architecture=${architecture}, ostree.bootable=${bootable})." >&2
    exit 1
  fi
  echo "Verified bootable ARM64 image: ${image}"
}

# Verify that all pushed images share the same first N base layers as the base.
verify_chain_coherence() {
  local base="$1"; shift
  local children=("$@")
  echo "==> Verifying layer-chain coherence across all demo images"

  # Number of layers in the base image — all children must start with these.
  local base_layers
  base_layers="$(podman image inspect --format '{{len .RootFS.Layers}}' "${base}")"
  local base_layer_list
  base_layer_list="$(podman image inspect --format '{{range .RootFS.Layers}}{{.}} {{end}}' "${base}")"

  local ok=1
  for child in "${children[@]}"; do
    local child_layer_list
    child_layer_list="$(podman image inspect --format '{{range .RootFS.Layers}}{{.}} {{end}}' "${child}")"
    # The child's first base_layers entries must equal the base's layers exactly.
    local child_base_prefix
    child_base_prefix="$(echo "${child_layer_list}" | tr ' ' '\n' | head -n "${base_layers}" | tr '\n' ' ')"
    if [[ "${child_base_prefix}" != "${base_layer_list}" ]]; then
      echo "ERROR: ${child} does NOT share the base layer chain of ${base}." >&2
      echo "  Expected prefix: ${base_layer_list}" >&2
      echo "  Got prefix:      ${child_base_prefix}" >&2
      ok=0
    else
      echo "  ✓ ${child} shares all ${base_layers} base layers"
    fi
  done
  [[ "${ok}" == "1" ]] || exit 1
}

sign_image_with_cosign() {
  local image="$1"
  echo "==> Signing ${image} with local Cosign helper"
  (cd "${REPO_DIR}" && IMAGE="${image}" ./scripts/local-sign-keyless.sh)
}

build_ocpvirt_disk() {
  local image="$1"
  local disk_image="$2"
  local branch run_id dispatch_output

  branch="$(git -C "${REPO_DIR}" branch --show-current)"
  if [[ -z "${branch}" ]]; then
    echo "ERROR: cannot dispatch build-sign-push.yml from a detached HEAD." >&2
    exit 1
  fi

  echo "==> Dispatching build-sign-push.yml for branch ${branch}"
  dispatch_output="$(gh workflow run build-sign-push.yml --ref "${branch}" 2>&1)"
  printf '%s\n' "${dispatch_output}"

  run_id="$(printf '%s\n' "${dispatch_output}" | \
    sed -nE 's#^https://github\.com/[^/]+/[^/]+/actions/runs/([0-9]+).*#\1#p' | head -n 1)"
  [[ -n "${run_id}" ]] || { echo "ERROR: could not determine dispatched run ID." >&2; exit 1; }

  echo "==> Waiting for GitHub Actions run ${run_id}"
  gh run watch "${run_id}" --exit-status

  skopeo inspect "docker://${disk_image}" >/dev/null 2>&1 || {
    echo "ERROR: AMD64 disk image not found after workflow: ${disk_image}" >&2; exit 1
  }
}

# ─────────────────────────────────────────────────────────────────────────────
require_command podman
require_command skopeo
require_command gh

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: run this preparation script on an ARM64 Mac, not ${HOSTTYPE:-unknown}." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}" "${AI_LAB_RECIPES_TMP_DIR:-}"' EXIT
mkdir -p "${TMP_DIR}/update" "${TMP_DIR}/broken" "${TMP_DIR}/fixed"

# ── STEP 1: Prepare AI Lab chatbot quadlet ────────────────────────────────────
if [[ "${ADD_CHATBOT}" == "1" ]]; then
  require_command git
  require_command make
  if [[ -z "${AI_LAB_RECIPES_DIR}" ]]; then
    AI_LAB_RECIPES_TMP_DIR="$(mktemp -d)"
    git clone --depth 1 https://github.com/containers/ai-lab-recipes.git "${AI_LAB_RECIPES_TMP_DIR}"
    AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_TMP_DIR}"
  fi
  RECIPE_DIR="${AI_LAB_RECIPES_DIR}/recipes/natural_language_processing/chatbot"
  [[ -d "${RECIPE_DIR}" ]] || { echo "ERROR: chatbot recipe not found: ${RECIPE_DIR}" >&2; exit 1; }
  make -C "${RECIPE_DIR}" quadlet
  for artifact in chatbot.kube chatbot.yaml; do
    [[ -s "${RECIPE_DIR}/build/${artifact}" ]] || {
      echo "ERROR: AI Lab Recipes did not generate ${artifact}." >&2; exit 1
    }
  done

  cp "${RECIPE_DIR}/build/chatbot.yaml" "${TMP_DIR}/update/"

  # chatbot.kube — WantedBy=multi-user.target so it never blocks boot.
  # TimeoutStartSec=1800 gives the ~7 GB model images time to pull on first boot.
  cat > "${TMP_DIR}/update/chatbot.kube" <<'EOF'
[Unit]
Description=Chatbot pod from AI Lab recipe
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Kube]
Yaml=chatbot.yaml

[Service]
Restart=on-failure
RestartSec=30
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF
fi

# ── STEP 2: Build base image ──────────────────────────────────────────────────
if [[ "${REBUILD_GOOD}" == "1" ]] || ! podman image exists "${IMAGE_GOOD}"; then
  echo "==> Building ${IMAGE_GOOD} from the repository Containerfile"
  (cd "${REPO_DIR}" && ./scripts/local-build.sh)
  podman image exists "${SOURCE_IMAGE_ARM}" || {
    echo "ERROR: expected local baseline image was not built: ${SOURCE_IMAGE_ARM}" >&2; exit 1
  }
  podman tag "${SOURCE_IMAGE_ARM}" "${IMAGE_GOOD}"
else
  echo "==> Reusing existing local ${IMAGE_GOOD}"
fi

assert_bootable_arm64 "${IMAGE_GOOD}"

# ── STEP 3: Push base image and pin its digest ────────────────────────────────
# CRITICAL: push first so the qcow2 and all child images use the exact same
# content that is now live in Quay — not a mutable local tag.
BASE_DIGEST=""
if [[ "${PUSH_IMAGES}" == "1" ]]; then
  push_and_capture "${IMAGE_GOOD}" BASE_DIGEST
else
  # No push requested — use the local image ID as the pin so children still
  # build consistently, but warn that Quay may be out of sync.
  BASE_DIGEST="$(podman image inspect --format '{{.Id}}' "${IMAGE_GOOD}")"
  echo "WARNING: PUSH_IMAGES=0 — children will be built from local content only." \
       "Quay may not match. Set PUSH_IMAGES=1 for a coherent demo." >&2
fi

# Construct the digest-pinned FROM reference.
# When pushed, this is  quay.io/…:demo-v1-arm64@sha256:…
# When not pushed, fall back to  quay.io/…:demo-v1-arm64  (local tag)
if [[ "${PUSH_IMAGES}" == "1" ]]; then
  PINNED_BASE="${IMAGE_GOOD%:*}@${BASE_DIGEST}"
else
  PINNED_BASE="${IMAGE_GOOD}"
fi
echo "INFO: child images will be built FROM ${PINNED_BASE}"

# ── STEP 4: Build UTM qcow2 disk from the pinned base ────────────────────────
# The disk is built from the same content that is now in Quay, so the VM that
# boots from this disk and the images it will bootc-switch to share a root.
if [[ "${BUILD_UTM_DISK}" == "1" ]]; then
  echo "==> Building UTM ARM64 qcow2 from ${IMAGE_GOOD} (Quay digest: ${BASE_DIGEST})"
  (cd "${REPO_DIR}" && \
    IMAGE_ARM="${IMAGE_GOOD}" \
    DISK_IMAGE_ARM="${DISK_IMAGE_GOOD}" \
    ./scripts/local-build-qcow2.sh)
fi

if [[ "${BUILD_OCPVIRT_DISK}" == "1" ]]; then
  build_ocpvirt_disk "${IMAGE_AMD}" "${DISK_IMAGE_AMD}"
fi

# ── STEP 5: Generate child Containerfiles pinned to the base digest ───────────

# update (v2 chatbot)
{
  echo "FROM ${PINNED_BASE}"
  echo "RUN mkdir -p /usr/share/www/html /usr/lib/tmpfiles.d && \\"
  echo "    echo 'L+ /var/www/html/index.html - - - - /usr/share/www/html/index.html' > /usr/lib/tmpfiles.d/00-demo-html.conf"
  echo "COPY index.html /usr/share/www/html/index.html"
  echo "COPY index.html /var/www/html/index.html"
  if [[ "${ADD_CHATBOT}" == "1" ]]; then
    echo "COPY chatbot.kube chatbot.yaml /usr/share/containers/systemd/"
  fi
  echo "LABEL org.opencontainers.image.title=\"RHEL Image Mode demo v2\""
} > "${TMP_DIR}/update/Containerfile"

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

# ── STEP 6: Build and push IMAGE_UPDATE, then pin broken/fixed to its digest ──
echo "==> Building ${IMAGE_UPDATE}"
build_child "${IMAGE_UPDATE}" "${TMP_DIR}/update"
assert_bootable_arm64 "${IMAGE_UPDATE}"

UPDATE_DIGEST=""
if [[ "${PUSH_IMAGES}" == "1" ]]; then
  push_and_capture "${IMAGE_UPDATE}" UPDATE_DIGEST
  PINNED_UPDATE="${IMAGE_UPDATE%:*}@${UPDATE_DIGEST}"
else
  UPDATE_DIGEST="$(podman image inspect --format '{{.Id}}' "${IMAGE_UPDATE}")"
  PINNED_UPDATE="${IMAGE_UPDATE}"
fi
echo "INFO: broken/fixed images will be built FROM ${PINNED_UPDATE}"

# broken — built from pinned IMAGE_UPDATE
cat > "${TMP_DIR}/broken/Containerfile" <<EOF
FROM ${PINNED_UPDATE}
RUN systemctl mask httpd
LABEL org.opencontainers.image.title="RHEL Image Mode demo broken"
EOF

# fixed — also built from pinned IMAGE_UPDATE
cat > "${TMP_DIR}/fixed/Containerfile" <<EOF
FROM ${PINNED_UPDATE}
RUN systemctl unmask httpd && systemctl enable httpd
RUN mkdir -p /usr/share/www/html /usr/lib/tmpfiles.d && \\
    echo 'L+ /var/www/html/index.html - - - - /usr/share/www/html/index.html' > /usr/lib/tmpfiles.d/00-demo-html.conf
COPY index.html /usr/share/www/html/index.html
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

echo "==> Building ${IMAGE_BROKEN} and ${IMAGE_FIXED}"
build_child "${IMAGE_BROKEN}" "${TMP_DIR}/broken"
build_child "${IMAGE_FIXED}"  "${TMP_DIR}/fixed"

assert_bootable_arm64 "${IMAGE_BROKEN}"
assert_bootable_arm64 "${IMAGE_FIXED}"

# ── STEP 7: Push remaining children ──────────────────────────────────────────
BROKEN_DIGEST=""
FIXED_DIGEST=""
if [[ "${PUSH_IMAGES}" == "1" ]]; then
  push_and_capture "${IMAGE_BROKEN}" BROKEN_DIGEST
  push_and_capture "${IMAGE_FIXED}"  FIXED_DIGEST
fi

# ── STEP 8: Verify the full layer-chain coherence ─────────────────────────────
verify_chain_coherence "${IMAGE_GOOD}" "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}"

# ── STEP 9: Sign all images ───────────────────────────────────────────────────
if [[ "${PUSH_IMAGES}" == "1" ]]; then
  echo "==> Signing demo images through the local Cosign helper"
  for image in "${IMAGE_GOOD}" "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}"; do
    sign_image_with_cosign "${image}"
  done
fi

# ── STEP 10: QEMU smoke-test (optional) ──────────────────────────────────────
if [[ "${TEST_QEMU}" == "1" ]]; then
  [[ "${PUSH_IMAGES}" == "1" ]] || {
    echo "ERROR: TEST_QEMU=1 requires PUSH_IMAGES=1 so the guest can pull each bootc image." >&2
    exit 1
  }
  DISK_IMAGE_PATH="${REPO_DIR}/output/qcow2/disk-arm.qcow2" \
    "${SCRIPT_DIR}/test-bootc-images-qemu.sh"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "Prepared images (all share the same base layer chain):"
printf '  %-45s  %s\n' "${IMAGE_GOOD}"   "${BASE_DIGEST}"
printf '  %-45s  %s\n' "${IMAGE_UPDATE}" "${UPDATE_DIGEST}"
printf '  %-45s  %s\n' "${IMAGE_BROKEN}" "${BROKEN_DIGEST}"
printf '  %-45s  %s\n' "${IMAGE_FIXED}"  "${FIXED_DIGEST}"
echo
echo "UTM disk  : ${DISK_IMAGE_GOOD}  →  output/qcow2/disk-arm.qcow2"
echo "OCP disk  : ${DISK_IMAGE_AMD}   (built by GitHub Actions)"
