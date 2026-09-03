#!/usr/bin/env bash
set -euo pipefail

# RHEL Image Mode demo for an Apple Silicon Mac and an ARM64 UTM VM.
# Heavy builds and disk conversion happen before the session; this script
# demonstrates the operational lifecycle with pre-published images.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${CHATBOT_PORT:=8501}"
: "${RUN_CHATBOT_EXTENSION:=1}"
: "${AI_LAB_RECIPES_DIR:=}"
: "${VM_SSH:=demo@192.168.64.9}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_REBOOT_TIMEOUT:=240}"
: "${RUN_SNO_EXTENSION:=0}"
: "${RUN_FLEET_EXTENSION:=1}"
: "${FLEET_APPLY:=0}"

BOLD='\033[1m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RED='\033[1;31m'
RESET='\033[0m'

pause() {
  local message="${1:-Press ENTER to continue...}"
  echo
  echo -e "${BOLD}  ${message}${RESET}"
  read -r
}

step() {
  echo
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  STEP $1: $2${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo
  pause "Press ENTER to start step $1..."
}

say() {
  echo -e "${YELLOW}  ▶  $*${RESET}"
}

note() {
  echo -e "${BLUE}  ℹ  $*${RESET}"
}

run() {
  echo -e "${GREEN}  \$ $*${RESET}"
  "$@"
}

remote() {
  ssh -i "${VM_SSH_KEY}" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 \
    "${VM_SSH}" "$@"
}

wait_for_vm() {
  local elapsed=0
  note "Waiting for ${VM_SSH} to accept SSH (up to ${VM_REBOOT_TIMEOUT}s)..."

  # A reboot command can return before sshd has stopped. Require one failed
  # connection first, otherwise we may mistake the old boot for the new one.
  while (( elapsed < VM_REBOOT_TIMEOUT )); do
    if ! remote true >/dev/null 2>&1; then
      break
    fi
    ((elapsed += 5))
    sleep 5
  done

  while (( elapsed < VM_REBOOT_TIMEOUT )); do
    if remote true >/dev/null 2>&1; then
      note "VM is reachable again after ${elapsed}s."
      return 0
    fi
    ((elapsed += 5))
    sleep 5
    if (( elapsed % 30 == 0 )); then
      note "Still waiting for VM reboot (${elapsed}/${VM_REBOOT_TIMEOUT}s)..."
    fi
  done
  echo -e "${RED}  VM did not become reachable within ${VM_REBOOT_TIMEOUT}s. The reboot may still be in progress; check UTM and retry the SSH check.${RESET}" >&2
  return 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}  Required command not found: $1${RESET}" >&2
    exit 1
  }
}

show_config() {
  note "GOOD   = ${IMAGE_GOOD}"
  note "UPDATE = ${IMAGE_UPDATE}"
  note "BROKEN = ${IMAGE_BROKEN}"
  note "FIXED  = ${IMAGE_FIXED}"
  note "AI chatbot = AI Lab Recipes chatbot (localhost:${CHATBOT_PORT})"
  note "UTM VM = ${VM_SSH}"
  note "All images and the ARM64 qcow2 disk must be prepared before the demo."
}

require_command podman
require_command ssh
[[ -f "${VM_SSH_KEY}" ]] || {
  echo -e "${RED}  SSH key not found: ${VM_SSH_KEY}${RESET}" >&2
  exit 1
}

check_images() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Pre-flight: Verifying images${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  
  local images=("${IMAGE_GOOD}" "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}")
  
  for img in "${images[@]}"; do
    if podman inspect "$img" >/dev/null 2>&1; then
      echo -e "${GREEN}  ✅ $img found${RESET}"
    else
      echo -e "${RED}  ❌ $img not found. Please run: podman pull $img${RESET}"
      exit 1
    fi
  done
  echo ""
}

clear
echo -e "${CYAN}${BOLD}"
echo "  RHEL Image Mode: pets -> cattle -> immutable reality"
echo "  Apple Silicon Mac M5 + ARM64 UTM VM"
echo -e "${RESET}"
show_config
check_images
pause "Press ENTER to start the demo..."

step 1 "See the image model"
say "The repository defines the operating system as a bootable image."
say "A golden image is reused by the service and webpage images."
say "The VM is a deployed version of an image, not the source of truth."
pause

step 2 "Test the image as a container"
say "The same bootc image can be tested with ordinary container tooling."
run podman pull "${IMAGE_GOOD}"
run podman rm -f bootc-demo-test 2>/dev/null || true
run podman run --rm -d --name bootc-demo-test -p 8080:80 "${IMAGE_GOOD}"
pause "Open http://localhost:8080, then press ENTER..."
run podman stop bootc-demo-test

step "2b" "Verify signing and digest in Quay"
say "Every pushed image is signed with keyless Cosign (OIDC – no long-lived key)."
say "skopeo inspect shows the digest that ties Quay, the VM and the git commit together."
note "Signing is done by: ./scripts/local-sign-keyless.sh"
run skopeo inspect --raw "docker://${IMAGE_GOOD}" | python3 -m json.tool | head -30
note "Cosign verification:"
run cosign verify \
  --certificate-identity-regexp="https://github.com/waltherB/rhel10-bootc-github-quay-demo" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
cosign verify \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
  note "Signature not found for this tag – expected when using pre-built demo images."
pause "Slide: Quay – digest, tag og signering. Press ENTER to continue..."

step "2c" "Promote dev → prod (gh workflow dispatch)"
say "Promotion uses skopeo copy – same digest, just a new :prod tag."
say "No rebuild: what was tested in CI is exactly what goes to prod."
note "Triggering: gh workflow run promote-rhel10-bootc-prod.yml --field source_tag=demo-v1-arm64"
run gh workflow run promote-prod.yml \
  --repo waltherB/rhel10-bootc-github-quay-demo \
  --field source_tag=demo-v1-arm64 || \
  note "gh workflow dispatch skipped – run manually if needed."
note "Watch progress: gh run list --workflow=promote-prod.yml --limit 3"
run gh run list --repo waltherB/rhel10-bootc-github-quay-demo \
  --workflow=promote-prod.yml --limit 3 || true
pause "Slide: Promotion bør flytte referencen, ikke genbygge indholdet. Press ENTER..."

step 3 "Inspect the running UTM VM"
say "Now the same image model is running as a full RHEL VM."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

step 4 "Test the AI chatbot pod as containers"
say "We test the AI Lab Recipes container before putting it in the OS image."
say "Podman Desktop can show the container, logs, port and image metadata here."
if [[ "${RUN_CHATBOT_EXTENSION}" == "1" ]]; then
  run env AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_DIR}" \
    CHATBOT_PORT="${CHATBOT_PORT}" \
    ./scripts/test-chatbot-container-m5.sh
else
  note "RUN_CHATBOT_EXTENSION=0; skipping chatbot test."
fi

step 5 "Deploy the chatbot through a bootc update"
say "The next image contains the chatbot as a systemd Quadlet."
say "The container is now part of the image definition and starts with the VM."
if [[ "${RUN_CHATBOT_EXTENSION}" != "1" ]]; then
  note "RUN_CHATBOT_EXTENSION=0; skipping chatbot deployment."
else
  run remote sudo bootc switch "${IMAGE_UPDATE}"
  run remote sudo bootc status
  pause "The chatbot image is staged. Press ENTER to reboot the VM..."
  run remote sudo systemctl reboot || true
  wait_for_vm
  run remote sudo bootc status
  run remote sudo systemctl daemon-reload
  run remote sudo systemctl --no-pager --full status chatbot.service || true
  run remote sudo systemctl list-unit-files --all | grep -Ei 'chatbot|llamacpp' || true
  note "The chatbot should be available on the VM's port ${CHATBOT_PORT}."
fi

step 6 "Inspect the updated VM"
say "A workload change is delivered as a new image, not as manual host changes."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

step 7 "Deploy a deliberately broken version"
say "This version contains a known mistake: the HTTP service is not enabled."
say "The failure makes rollback visible and gives the audience a real recovery path."
run remote sudo bootc switch "${IMAGE_BROKEN}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo systemctl --no-pager --full status httpd || true
run remote curl -fsS http://localhost | lynx -stdin -dump || true
run remote sudo bootc status
pause

step 8 "Rollback to the known-good deployment"
say "bootc keeps the previous deployment as a rollback target."
run remote sudo bootc rollback --apply || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

step 9 "Deploy the fixed image"
say "The fix is built once, tested, and delivered as a new image version."
run remote sudo bootc switch "${IMAGE_FIXED}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

if [[ "${RUN_FLEET_EXTENSION}" == "1" ]]; then
  step 10 "One repository update, many VM deployments"
  say "The tested image can be applied to a fleet using the same target reference."
  say "The default is plan-only; no additional VMs are required for this demo."
  note "Example fleet: demo-web-01 (.20) demo-web-02 (.21) demo-web-03 (.22) demo-web-04 (.23)"
  run env IMAGE_UPDATE="${VM_TARGETS}" \
    VM_TARGETS="${IMAGE_FIXED}" \
    FLEET_APPLY="${FLEET_APPLY}" ./scripts/demo-fleet-update-m5.sh
  pause "Press ENTER to continue..."
fi

if [[ "${RUN_SNO_EXTENSION}" == "1" ]]; then
  step 11 "Optional: the same model on OpenShift Virtualization"
  say "The local demo used ARM64 in UTM; the SNO extension uses a prebuilt AMD64 image."
  say "OpenShift manages the VM platform while bootc manages the guest OS lifecycle."
  note "Show the prepared VirtualMachine, its DataVolume, and bootc status over SSH."
  pause
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
say "Cleaning up demo resources..."
run podman rm -f bootc-demo-test 2>/dev/null || true

echo -e "${GREEN}${BOLD}  Demo complete: build -> sign -> promote -> deploy -> fail -> rollback -> fix${RESET}"
