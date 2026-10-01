#!/usr/bin/env bash
set -euo pipefail

# Build and push only the demo-v2-chatbot-arm64 bootc image.
# Assumes the base image (IMAGE_GOOD / demo-v1-arm64) already exists locally.
# Use REBUILD_BASE=1 to force a rebuild of the base image first.

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_command podman
require_command git
require_command make

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: run this script on an ARM64 Mac, not ${HOSTTYPE:-unknown}." >&2
  exit 1
fi

# ── Base image ────────────────────────────────────────────────────────────────
if [[ "${REBUILD_BASE}" == "1" ]]; then
  echo "==> Rebuilding base image ${IMAGE_GOOD}"
  (cd "${REPO_DIR}" && ./scripts/local-build.sh)
  podman tag "${IMAGE_ARM:-${QUAY_REPO}:dev-arm64}" "${IMAGE_GOOD}"
elif ! podman image exists "${IMAGE_GOOD}"; then
  echo "ERROR: base image not found locally: ${IMAGE_GOOD}" >&2
  echo "       Run ./scripts/prepare-demo-m5.sh first, or set REBUILD_BASE=1." >&2
  exit 1
else
  echo "==> Using existing base image ${IMAGE_GOOD}"
fi

# ── AI Lab Recipes quadlet ────────────────────────────────────────────────────
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
[[ -d "${RECIPE_DIR}" ]] || {
  echo "ERROR: chatbot recipe not found: ${RECIPE_DIR}" >&2
  exit 1
}

echo "==> Running make quadlet"
make -C "${RECIPE_DIR}" quadlet

for artifact in chatbot.kube chatbot.yaml; do
  [[ -s "${RECIPE_DIR}/build/${artifact}" ]] || {
    echo "ERROR: AI Lab Recipes did not generate ${artifact}." >&2
    exit 1
  }
done

# ── Build context ─────────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"

cp "${RECIPE_DIR}/build/chatbot.yaml" "${TMP_DIR}/"
cp "${REPO_DIR}/files/demo-dns.nmconnection" "${TMP_DIR}/"

# Configure chatbot.kube:
# 1. WantedBy=multi-user.target (so it does NOT block default.target or system boot)
# 2. TimeoutStartSec=1800 (allows time to pull the ~7.3GB AI models from Quay in the background)
# 3. Restart=on-failure
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

cat > "${TMP_DIR}/Containerfile" <<EOF
FROM ${IMAGE_GOOD}
RUN mkdir -p /usr/share/www/html /usr/lib/tmpfiles.d && \
    echo 'L+ /var/www/html/index.html - - - - /usr/share/www/html/index.html' > /usr/lib/tmpfiles.d/00-demo-html.conf
COPY index.html /usr/share/www/html/index.html
COPY index.html /var/www/html/index.html
COPY chatbot.kube chatbot.yaml /usr/share/containers/systemd/
# Add network configuration for the demo
COPY demo-dns.nmconnection /etc/NetworkManager/system-connections/demo-dns.nmconnection
RUN chmod 600 /etc/NetworkManager/system-connections/demo-dns.nmconnection && \
    chown root:root /etc/NetworkManager/system-connections/demo-dns.nmconnection
LABEL org.opencontainers.image.title="RHEL Image Mode demo v2"
EOF

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Building ${IMAGE_UPDATE}"
podman build --no-cache --platform linux/arm64 -t "${IMAGE_UPDATE}" "${TMP_DIR}"

# ── Push ──────────────────────────────────────────────────────────────────────
if [[ "${PUSH_IMAGE}" == "1" ]]; then
  echo "==> Pushing ${IMAGE_UPDATE}"
  podman push "${IMAGE_UPDATE}"

  if [[ "${SIGN_IMAGE}" == "1" ]]; then
    echo "==> Signing ${IMAGE_UPDATE}"
    (cd "${REPO_DIR}" && IMAGE="${IMAGE_UPDATE}" ./scripts/local-sign-keyless.sh)
  fi
fi

echo
echo "Done: ${IMAGE_UPDATE}"
