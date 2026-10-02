#!/usr/bin/env bash
set -euo pipefail

# Build and push only the demo-v2-chatbot-arm64 bootc image.
#
# DIGEST COHERENCE GUARANTEE
# ───────────────────────────
# The child image is built FROM a digest-pinned reference of IMAGE_GOOD as it
# exists in Quay right now — not from a mutable local tag.  This guarantees that
# a VM booted from the demo-v1-arm64 qcow2 disk can always `bootc switch` to
# the freshly built chatbot image because they share the same base layer chain.
#
# Assumptions:
#   • IMAGE_GOOD (demo-v1-arm64) is already pushed to Quay.
#   • Use REBUILD_BASE=1 to rebuild it from scratch first.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-chatbot-arm64}"
: "${AI_LAB_RECIPES_DIR:=}"
: "${CHATBOT_PORT:=8501}"
: "${PUSH_IMAGE:=1}"
: "${SIGN_IMAGE:=1}"
: "${REBUILD_BASE:=0}"

# ─────────────────────────────────────────────────────────────────────────────
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
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

# Verify that IMAGE_UPDATE's base layers are a prefix of IMAGE_GOOD's layers.
verify_chain_coherence() {
  local base="$1"
  local child="$2"
  echo "==> Verifying layer-chain coherence: ${child} extends ${base}"
  local base_len base_layers child_prefix
  base_len="$(podman image inspect --format '{{len .RootFS.Layers}}' "${base}")"
  base_layers="$(podman image inspect --format '{{range .RootFS.Layers}}{{.}} {{end}}' "${base}")"
  child_prefix="$(podman image inspect --format '{{range .RootFS.Layers}}{{.}} {{end}}' "${child}" \
    | tr ' ' '\n' | head -n "${base_len}" | tr '\n' ' ')"
  if [[ "${child_prefix}" != "${base_layers}" ]]; then
    echo "ERROR: ${child} does NOT share the base layer chain of ${base}." >&2
    echo "  Expected prefix: ${base_layers}" >&2
    echo "  Got prefix:      ${child_prefix}" >&2
    exit 1
  fi
  echo "  ✓ ${child} shares all ${base_len} base layers of ${base}"
}

# ─────────────────────────────────────────────────────────────────────────────
require_command podman
require_command skopeo
require_command git
require_command make

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: run this script on an ARM64 Mac, not ${HOSTTYPE:-unknown}." >&2
  exit 1
fi

# ── STEP 1: Ensure base image is present locally and in Quay ─────────────────
if [[ "${REBUILD_BASE}" == "1" ]]; then
  echo "==> Rebuilding base image ${IMAGE_GOOD}"
  (cd "${REPO_DIR}" && ./scripts/local-build.sh)
  podman tag "${IMAGE_ARM:-${QUAY_REPO}:dev-arm64}" "${IMAGE_GOOD}"
  echo "==> Pushing rebuilt base ${IMAGE_GOOD}"
  podman push "${IMAGE_GOOD}"
elif ! podman image exists "${IMAGE_GOOD}"; then
  echo "==> Base image not found locally — pulling from Quay"
  podman pull "${IMAGE_GOOD}" || {
    echo "ERROR: ${IMAGE_GOOD} not found locally or in Quay." >&2
    echo "       Run ./scripts/prepare-demo-m5.sh first, or set REBUILD_BASE=1." >&2
    exit 1
  }
else
  echo "==> Using existing local ${IMAGE_GOOD}"
fi

assert_bootable_arm64 "${IMAGE_GOOD}"

# ── STEP 2: Resolve the Quay digest of IMAGE_GOOD and pin the FROM ───────────
# We resolve from Quay (not from local storage) so the pin points to exactly
# what is in the registry — the same content the VM boots from via the qcow2.
echo "==> Resolving Quay digest of ${IMAGE_GOOD}"
BASE_DIGEST=""
if [[ "${PUSH_IMAGE}" == "1" ]]; then
  # After any push in STEP 1, or for an existing tag, get the remote digest.
  BASE_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE_GOOD}")"
else
  # No push mode — use the local image ID; warn that Quay may differ.
  BASE_DIGEST="$(podman image inspect --format '{{.Id}}' "${IMAGE_GOOD}")"
  echo "WARNING: PUSH_IMAGE=0 — using local image ID as pin. Quay may differ." >&2
fi
[[ -n "${BASE_DIGEST}" ]] || { echo "ERROR: could not resolve digest for ${IMAGE_GOOD}" >&2; exit 1; }

if [[ "${PUSH_IMAGE}" == "1" ]]; then
  PINNED_BASE="${IMAGE_GOOD%:*}@${BASE_DIGEST}"
else
  PINNED_BASE="${IMAGE_GOOD}"
fi
echo "INFO: chatbot image will be built FROM ${PINNED_BASE}"

# ── STEP 3: Prepare AI Lab chatbot quadlet ────────────────────────────────────
AI_LAB_RECIPES_TMP_DIR=""
if [[ -z "${AI_LAB_RECIPES_DIR}" ]]; then
  AI_LAB_RECIPES_TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR:-}" "${AI_LAB_RECIPES_TMP_DIR}"' EXIT
  echo "==> Cloning ai-lab-recipes"
  git clone --depth 1 https://github.com/containers/ai-lab-recipes.git "${AI_LAB_RECIPES_TMP_DIR}"
  AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_TMP_DIR}"
else
  trap 'rm -rf "${TMP_DIR:-}"' EXIT
fi

RECIPE_DIR="${AI_LAB_RECIPES_DIR}/recipes/natural_language_processing/chatbot"
[[ -d "${RECIPE_DIR}" ]] || { echo "ERROR: chatbot recipe not found: ${RECIPE_DIR}" >&2; exit 1; }

echo "==> Running make quadlet"
make -C "${RECIPE_DIR}" quadlet

for artifact in chatbot.kube chatbot.yaml; do
  [[ -s "${RECIPE_DIR}/build/${artifact}" ]] || {
    echo "ERROR: AI Lab Recipes did not generate ${artifact}." >&2; exit 1
  }
done

# ── STEP 4: Assemble build context ───────────────────────────────────────────
TMP_DIR="$(mktemp -d)"

cp "${RECIPE_DIR}/build/chatbot.yaml" "${TMP_DIR}/"

# chatbot.kube — WantedBy=multi-user.target so it never blocks boot.
# TimeoutStartSec=1800 gives the ~7 GB model images time to pull on first boot.
cat > "${TMP_DIR}/chatbot.kube" <<'EOF'
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

cat > "${TMP_DIR}/index.html" <<'EOF'
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

# Containerfile uses the digest-pinned FROM
cat > "${TMP_DIR}/Containerfile" <<EOF
FROM ${PINNED_BASE}
RUN mkdir -p /usr/share/www/html /usr/lib/tmpfiles.d && \\
    echo 'L+ /var/www/html/index.html - - - - /usr/share/www/html/index.html' > /usr/lib/tmpfiles.d/00-demo-html.conf
COPY index.html /usr/share/www/html/index.html
COPY index.html /var/www/html/index.html
COPY chatbot.kube chatbot.yaml /usr/share/containers/systemd/
LABEL org.opencontainers.image.title="RHEL Image Mode demo v2"
EOF

# ── STEP 5: Build ─────────────────────────────────────────────────────────────
echo "==> Building ${IMAGE_UPDATE}"
podman build --no-cache --pull=never --platform linux/arm64 -t "${IMAGE_UPDATE}" "${TMP_DIR}"

assert_bootable_arm64 "${IMAGE_UPDATE}"
verify_chain_coherence "${IMAGE_GOOD}" "${IMAGE_UPDATE}"

# ── STEP 6: Push and sign ─────────────────────────────────────────────────────
if [[ "${PUSH_IMAGE}" == "1" ]]; then
  echo "==> Pushing ${IMAGE_UPDATE}"
  podman push "${IMAGE_UPDATE}"

  UPDATE_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE_UPDATE}")"
  echo "INFO: ${IMAGE_UPDATE} pushed → ${UPDATE_DIGEST}"

  if [[ "${SIGN_IMAGE}" == "1" ]]; then
    echo "==> Signing ${IMAGE_UPDATE}"
    (cd "${REPO_DIR}" && IMAGE="${IMAGE_UPDATE}" ./scripts/local-sign-keyless.sh)
  fi
fi

echo
echo "Done:"
printf '  base   : %-45s  %s\n' "${IMAGE_GOOD}"   "${BASE_DIGEST}"
printf '  chatbot: %-45s  %s\n' "${IMAGE_UPDATE}" "${UPDATE_DIGEST:-<not pushed>}"
