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
: "${VM_SSH:=demo@192.168.64.9}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_REBOOT_TIMEOUT:=90}"
: "${RUN_SNO_EXTENSION:=0}"

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
  while (( elapsed < VM_REBOOT_TIMEOUT )); do
    if remote true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    ((elapsed += 5))
  done
  echo -e "${RED}  VM did not become reachable within ${VM_REBOOT_TIMEOUT}s.${RESET}" >&2
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
  note "UTM VM = ${VM_SSH}"
  note "All images and the ARM64 qcow2 disk must be prepared before the demo."
}

require_command podman
require_command ssh
[[ -f "${VM_SSH_KEY}" ]] || {
  echo -e "${RED}  SSH key not found: ${VM_SSH_KEY}${RESET}" >&2
  exit 1
}

clear
echo -e "${CYAN}${BOLD}"
echo "  RHEL Image Mode: pets -> cattle -> immutable reality"
echo "  Apple Silicon Mac M5 + ARM64 UTM VM"
echo -e "${RESET}"
show_config
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

step 3 "Inspect the running UTM VM"
say "Now the same image model is running as a full RHEL VM."
run remote sudo bootc status
run remote curl -fsS http://localhost
pause

step 4 "Deploy a new image"
say "A workload change is delivered as a new image, not as manual host changes."
run remote sudo bootc switch "${IMAGE_UPDATE}"
run remote sudo bootc status
pause "The update is staged. Press ENTER to reboot the VM..."
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost
pause

step 5 "Deploy a deliberately broken version"
say "This version contains a known mistake: the HTTP service is not enabled."
say "The failure makes rollback visible and gives the audience a real recovery path."
run remote sudo bootc switch "${IMAGE_BROKEN}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo systemctl --no-pager --full status httpd || true
run remote curl -fsS http://localhost || true
run remote sudo bootc status
pause

step 6 "Rollback to the known-good deployment"
say "bootc keeps the previous deployment as a rollback target."
run remote sudo bootc rollback --apply || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost
pause

step 7 "Deploy the fixed image"
say "The fix is built once, tested, and delivered as a new image version."
run remote sudo bootc switch "${IMAGE_FIXED}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost
pause

if [[ "${RUN_SNO_EXTENSION}" == "1" ]]; then
  step 8 "Optional: the same model on OpenShift Virtualization"
  say "The local demo used ARM64 in UTM; the SNO extension uses a prebuilt AMD64 image."
  say "OpenShift manages the VM platform while bootc manages the guest OS lifecycle."
  note "Show the prepared VirtualMachine, its DataVolume, and bootc status over SSH."
  pause
fi

echo -e "${GREEN}${BOLD}  Demo complete: build -> deploy -> fail -> rollback -> fix${RESET}"
