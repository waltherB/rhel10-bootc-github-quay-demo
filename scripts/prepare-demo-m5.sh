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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

build_child() {
  local image="$1"
  local context="$2"
  podman build --no-cache --platform linux/arm64 -t "${image}" "${context}"
}

build_ocpvirt_disk() {
  local image="$1"
  local disk_image="$2"
  local branch
  local run_id

  branch="$(git -C "${REPO_DIR}" branch --show-current)"
  if [[ -z "${branch}" ]]; then
    echo "ERROR: cannot dispatch build-sign-push.yml from a detached HEAD." >&2
    echo "Check out the branch containing the AMD64 build changes first." >&2
    exit 1
  fi

  echo "==> Dispatching build-sign-push.yml for branch ${branch}"
  gh workflow run build-sign-push.yml --ref "${branch}"

  run_id="$(gh run list \
    --workflow build-sign-push.yml \
    --branch "${branch}" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')"
  if [[ -z "${run_id}" ]]; then
    echo "ERROR: could not find the dispatched build-sign-push.yml run." >&2
    exit 1
  fi

  echo "==> Waiting for GitHub Actions run ${run_id}"
  gh run watch "${run_id}" --exit-status

  echo "==> Checking for AMD64 OCP Virt disk produced by build-sign-push.yml"
  if ! skopeo inspect "docker://${disk_image}" >/dev/null 2>&1; then
    echo "ERROR: AMD64 disk image not found: ${disk_image}" >&2
    echo "The workflow completed, but did not publish the expected disk tag." >&2
    echo "Expected ${disk_image}, built from ${image}." >&2
    exit 1
  fi
}

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

if [[ "${ADD_CHATBOT}" == "1" ]]; then
  command -v git >/dev/null 2>&1 || { echo "ERROR: git is required for the AI Lab recipe." >&2; exit 1; }
  if [[ -z "${AI_LAB_RECIPES_DIR}" ]]; then
    AI_LAB_RECIPES_TMP_DIR="$(mktemp -d)"
    git clone --depth 1 https://github.com/containers/ai-lab-recipes.git "${AI_LAB_RECIPES_TMP_DIR}"
    AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_TMP_DIR}"
  fi
  RECIPE_DIR="${AI_LAB_RECIPES_DIR}/recipes/natural_language_processing/chatbot"
  [[ -d "${RECIPE_DIR}" ]] || { echo "ERROR: chatbot recipe not found: ${RECIPE_DIR}" >&2; exit 1; }
  command -v make >/dev/null 2>&1 || { echo "ERROR: make is required for the AI Lab recipe." >&2; exit 1; }
  make -C "${RECIPE_DIR}" quadlet
  for artifact in chatbot.kube chatbot.yaml chatbot.image; do
    [[ -s "${RECIPE_DIR}/build/${artifact}" ]] || {
      echo "ERROR: AI Lab Recipes did not generate ${artifact}." >&2
      exit 1
    }
  done
  cp "${RECIPE_DIR}/build/chatbot.kube" "${RECIPE_DIR}/build/chatbot.yaml" "${RECIPE_DIR}/build/chatbot.image" "${TMP_DIR}/update/"
fi

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

if [[ "${BUILD_UTM_DISK}" == "1" ]]; then
  echo "==> Building UTM ARM64 qcow2 from ${IMAGE_GOOD}"
  (cd "${REPO_DIR}" && \
    IMAGE_ARM="${IMAGE_GOOD}" \
    DISK_IMAGE_ARM="${DISK_IMAGE_GOOD}" \
    ./scripts/local-build-qcow2.sh)
fi

if [[ "${BUILD_OCPVIRT_DISK}" == "1" ]]; then
  build_ocpvirt_disk "${IMAGE_AMD}" "${DISK_IMAGE_AMD}"
fi

cat > "${TMP_DIR}/update/Containerfile" <<EOF
FROM ${IMAGE_GOOD}
COPY index.html /var/www/html/index.html
COPY chatbot.kube chatbot.yaml chatbot.image /usr/share/containers/systemd/
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
echo "UTM disk: ${DISK_IMAGE_GOOD} (output/qcow2/disk-arm.qcow2)"
echo "OCP Virt disk: ${DISK_IMAGE_AMD} (from ${IMAGE_AMD})"
