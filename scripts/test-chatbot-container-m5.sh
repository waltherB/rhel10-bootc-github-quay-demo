#!/usr/bin/env bash
set -euo pipefail

# Test the official AI Lab Recipes chatbot pod before placing it in a bootc image.
# The recipe consists of an application, model server and model image.

: "${CHATBOT_PORT:=8501}"
: "${CHATBOT_NAME:=chatbot}"
: "${AI_LAB_RECIPES_DIR:=}"

if [[ -z "${AI_LAB_RECIPES_DIR}" ]]; then
  AI_LAB_RECIPES_DIR="$(mktemp -d)"
  trap 'rm -rf "${AI_LAB_RECIPES_DIR}"' EXIT
  git clone --depth 1 https://github.com/containers/ai-lab-recipes.git "${AI_LAB_RECIPES_DIR}"
fi

RECIPE_DIR="${AI_LAB_RECIPES_DIR}/recipes/natural_language_processing/chatbot"
[[ -d "${RECIPE_DIR}" ]] || { echo "ERROR: chatbot recipe not found: ${RECIPE_DIR}" >&2; exit 1; }

command -v make >/dev/null 2>&1 || { echo "ERROR: make is required." >&2; exit 1; }
command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required." >&2; exit 1; }

make -C "${RECIPE_DIR}" quadlet

podman rm -f "${CHATBOT_NAME}" 2>/dev/null || true
trap 'podman kube down "${RECIPE_DIR}/build/chatbot.yaml" >/dev/null 2>&1 || true' EXIT

printf 'Starting AI Lab Recipes chatbot pod on port %s\n' "${CHATBOT_PORT}"
podman kube play --replace "${RECIPE_DIR}/build/chatbot.yaml"

echo
echo "Container is running. Inspect it in Podman Desktop."
echo "Published endpoint: http://localhost:${CHATBOT_PORT}"
echo
echo "Pod containers:"
podman ps --filter "pod=${CHATBOT_NAME}" --format '  {{.ID}}  {{.Names}}  {{.Status}}'
echo
echo "Container logs:"
while IFS= read -r container_id; do
  [[ -n "${container_id}" ]] || continue
  echo "--- ${container_id} ---"
  podman logs "${container_id}" || true
done < <(podman ps --filter "pod=${CHATBOT_NAME}" --format '{{.ID}}')
echo
echo "Stop with ENTER when the chatbot has been tested."
read -r
