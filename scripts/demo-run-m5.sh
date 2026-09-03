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
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-chatbot-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${CHATBOT_PORT:=8501}"
: "${RUN_CHATBOT_EXTENSION:=1}"
: "${AI_LAB_RECIPES_DIR:=}"
: "${VM_SSH:=demo@192.168.64.18}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_REBOOT_TIMEOUT:=240}"
: "${RUN_SNO_EXTENSION:=0}"
: "${RUN_FLEET_EXTENSION:=1}"
: "${FLEET_APPLY:=0}"
: "${VM_TARGETS:=demo@192.168.64.20 demo@192.168.64.21 demo@192.168.64.22 demo@192.168.64.23}"

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

ascii() {
  echo -e "${CYAN}$*${RESET}"
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
  note "Fleet  = ${VM_TARGETS}"
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

# ── Intro ─────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   RHEL 10 Image Mode Demo                                    ║"
echo "  ║   pets  →  cattle  →  immutable reality                      ║"
echo "  ║   Apple Silicon Mac M5  +  ARM64 UTM VM                      ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}"
echo "  Full demo flow:"
echo ""
echo "   ┌──────────────┐  ┌────────────┐  ┌──────────────┐  ┌──────────┐"
echo "   │ Git repo     │  │ Quay.io    │  │ UTM VM       │  │ Fleet    │"
echo "   │ Containerfile│  │ Registry   │  │ ARM64 RHEL   │  │ 4× VMs   │"
echo "   └──────┬───────┘  └─────┬──────┘  └──────┬───────┘  └────┬─────┘"
echo "          │  build+sign    │   bootc switch  │               │"
echo "          └───────────────►│◄────────────────┘   fleet apply │"
echo "                           │─────────────────────────────────►│"
echo "                           │  promote dev→prod"
echo "                           │  rollback preserved at all times"
echo -e "${RESET}"
pause "Press ENTER to start the demo..."
show_config
check_images
pause "Press ENTER to start the demo..."

# ── STEP 1 ────────────────────────────────────────────────────────────────────
step 1 "See the image model"

ascii "  What we're looking at:"
ascii ""
ascii "   ┌─────────────────────────────────────────────────────────────┐"
ascii "   │  Git repository  (single source of truth)                   │"
ascii "   │                                                             │"
ascii "   │   Containerfile  ──► defines the entire OS declaratively   │"
ascii "   │   files/          ──► motd, config, certs baked in         │"
ascii "   │   .github/        ──► CI builds, signs, pushes to Quay     │"
ascii "   │   scripts/        ──► local build + demo runner            │"
ascii "   └─────────────────────────────────────────────────────────────┘"
ascii ""
ascii "   The VM is a deployed instance of an image."
ascii "   The repo is the source of truth — not the running machine."
echo ""
say "The repository defines the operating system as a bootable image."
say "A golden image is reused by the service and webpage images."
say "The VM is a deployed version of an image, not the source of truth."
pause "Press ENTER to continue..."
# ── STEP 2 ────────────────────────────────────────────────────────────────────
step 2 "Test the image as a container"

ascii "  Same image, two runtimes:"
ascii ""
ascii "   ┌──────────────────────┐"
ascii "   │  Quay.io             │"
ascii "   │  :demo-v1-arm64      │"
ascii "   └──────────┬───────────┘"
ascii "              │  podman pull"
ascii "              ▼"
ascii "   ┌──────────────────────┐   podman run -p 8080:80"
ascii "   │  Local podman store  │ ──────────────────────────► http://localhost:8080"
ascii "   │  (arm64 image)       │"
ascii "   └──────────────────────┘"
ascii ""
ascii "   ✔  No VM needed — fast feedback loop before touching infrastructure"
echo ""
say "The same bootc image can be tested with ordinary container tooling."
pause "Press ENTER to continue..."
run podman pull "${IMAGE_GOOD}"
run podman rm -f bootc-demo-test 2>/dev/null || true
run podman run --rm -d --name bootc-demo-test -p 8080:80 "${IMAGE_GOOD}"
pause "Open http://localhost:8080 in a browser, then press ENTER..."
run podman stop bootc-demo-test

# ── STEP 2b ───────────────────────────────────────────────────────────────────
step "2b" "Verify signing and digest in Quay"

ascii "  Every image is signed at push time via keyless Cosign (OIDC):"
ascii ""
ascii "   ┌──────────────┐  cosign sign   ┌────────────────────────────────┐"
ascii "   │ local-sign-  │ ─────────────► │ Quay.io                        │"
ascii "   │ keyless.sh   │                │  image manifest  +  signature  │"
ascii "   └──────────────┘                │  (OCI referrer attached)       │"
ascii "                                   └────────────────────────────────┘"
ascii ""
ascii "   local-sign-keyless.sh does:"
ascii "     1. skopeo inspect → resolves tag to digest"
ascii "     2. cosign sign <repo>@<digest>  (OIDC, no long-lived key)"
ascii "     3. cosign verify  (confirms attachment in Quay)"
ascii ""
ascii "   Digest ties: Quay tag ↔ VM booted image ↔ git commit SHA"
echo ""
pause "Press ENTER to continue..."
say "Every pushed image is signed with keyless Cosign (OIDC – no long-lived key)."
say "skopeo inspect shows the digest that ties Quay, the VM and the git commit."
note "Signing is done by: ./scripts/local-sign-keyless.sh"
run skopeo inspect --raw "docker://${IMAGE_GOOD}" | python3 -m json.tool 2>/dev/null | head -30 || \
  run skopeo inspect --raw "docker://${IMAGE_GOOD}" | head -30
note "Cosign verification:"
run cosign verify \
  --certificate-identity-regexp="https://github.com/waltherB/rhel10-bootc-github-quay-demo" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
cosign verify \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
  note "Signature not found for this tag – sign with: IMAGE=${IMAGE_GOOD} ./scripts/local-sign-keyless.sh"

# ── STEP 2c ───────────────────────────────────────────────────────────────────
step "2c" "Promote dev → prod (gh workflow dispatch)"

ascii "  Promotion = skopeo copy, NOT a rebuild:"
ascii ""
ascii "   ┌───────────────────────┐  gh workflow run      ┌──────────────────┐"
ascii "   │ GitHub Actions        │ ─────────────────────► promote-prod.yml  │"
ascii "   │ promote-prod.yml      │                       └────────┬─────────┘"
ascii "   └───────────────────────┘                                │"
ascii "                                                            │ skopeo copy"
ascii "   ┌───────────────────────┐                               ▼"
ascii "   │ Quay :demo-v1-arm64   │ ─────────────────────► Quay :prod-arm64  │"
ascii "   │ (digest unchanged)    │    same SHA digest     └──────────────────┘"
ascii "   └───────────────────────┘"
ascii ""
ascii "   ✔  What was tested in CI is exactly what runs in prod — no surprises"
echo ""
say "Promotion uses skopeo copy – same digest, just a new :prod tag."
say "No rebuild: what was tested in CI is exactly what goes to prod."
note "Triggering: gh workflow run promote-prod.yml --field source_tag=demo-v1-arm64"
pause "Press ENTER to continue..."
run gh workflow run promote-prod.yml \
  --repo waltherB/rhel10-bootc-github-quay-demo \
  --field source_tag=demo-v1-arm64 || \
  note "gh workflow dispatch skipped – run manually if needed."
note "Watching progress..."
run gh run watch --repo waltherB/rhel10-bootc-github-quay-demo || true

# ── STEP 3 ────────────────────────────────────────────────────────────────────
step 3 "Inspect the running UTM VM"

ascii "  The same image is now a full RHEL OS running inside UTM:"
ascii ""
ascii "   ┌──────────────────────┐  ssh ${VM_SSH}"
ascii "   │  Mac (this machine)  │ ─────────────────────────────────────────►"
ascii "   └──────────────────────┘                                           │"
ascii "                                              ┌────────────────────────┴──────┐"
ascii "                                              │  UTM VM  (ARM64 RHEL 10)      │"
ascii "                                              │                               │"
ascii "                                              │  sudo bootc status            │"
ascii "                                              │    booted: :demo-v1-arm64     │"
ascii "                                              │    staged:  (none)            │"
ascii "                                              │                               │"
ascii "                                              │  curl http://localhost        │"
ascii "                                              │    → web page from image      │"
ascii "                                              └───────────────────────────────┘"
echo ""
say "Now the same image model is running as a full RHEL VM."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── STEP 4 ────────────────────────────────────────────────────────────────────
step 4 "Test the AI chatbot pod as containers"

ascii "  Before baking the chatbot into the OS image, we test it as a plain pod:"
ascii ""
ascii "   test-chatbot-container-m5.sh does:"
ascii ""
ascii "   1. Clone ai-lab-recipes  (or use AI_LAB_RECIPES_DIR if set)"
ascii "      └─► github.com/containers/ai-lab-recipes"
ascii ""
ascii "   2. make quadlet  →  generates chatbot.yaml (Podman Kube manifest)"
ascii "      ┌──────────────────────────────────────────────────┐"
ascii "      │  chatbot.yaml contains:                          │"
ascii "      │    - app container   (Streamlit UI)              │"
ascii "      │    - model server    (llama.cpp)                 │"
ascii "      │    - model image     (GGUF weights)              │"
ascii "      └──────────────────────────────────────────────────┘"
ascii ""
ascii "   3. podman kube play chatbot.yaml"
ascii "      └─► pod running on localhost:${CHATBOT_PORT}"
ascii ""
ascii "   ✔  Same Quadlet definition goes into the bootc image in Step 5"
echo ""
say "We test the AI Lab Recipes container before putting it in the OS image."
say "Podman Desktop can show the container, logs, port and image metadata here."
pause "Press ENTER to continue..."
if [[ "${RUN_CHATBOT_EXTENSION}" == "1" ]]; then
  run env AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_DIR}" \
    CHATBOT_PORT="${CHATBOT_PORT}" \
    ./scripts/test-chatbot-container-m5.sh
else
  note "RUN_CHATBOT_EXTENSION=0; skipping chatbot test."
fi

# ── STEP 5 ────────────────────────────────────────────────────────────────────
step 5 "Deploy the chatbot through a bootc update"

ascii "  Workload delivery via image update — no SSH config, no Ansible on the host:"
ascii ""
ascii "   ┌──────────────────────┐  bootc switch          ┌────────────────────────┐"
ascii "   │ Quay                 │ ◄───────────────────── │  UTM VM                │"
ascii "   │ :demo-v2-chatbot     │   pulls new layers      │  (fetches from Quay)   │"
ascii "   └──────────────────────┘                        └────────────┬───────────┘"
ascii "                                                                │ systemctl reboot"
ascii "                                                                ▼"
ascii "                                                   ┌────────────────────────┐"
ascii "                                                   │  UTM VM (rebooted)     │"
ascii "                                                   │                        │"
ascii "                                                   │  chatbot.service       │"
ascii "                                                   │  (systemd Quadlet)     │"
ascii "                                                   │  → localhost:${CHATBOT_PORT}      │"
ascii "                                                   └────────────────────────┘"
ascii ""
ascii "   The chatbot Quadlet is baked into :demo-v2-chatbot — it starts"
ascii "   automatically on every boot, managed by systemd, no manual steps."
echo ""
say "The next image contains the chatbot as a systemd Quadlet."
say "The container is now part of the image definition and starts with the VM."
pause "Press ENTER to continue..."
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

# ── STEP 6 ────────────────────────────────────────────────────────────────────
step 6 "Inspect the updated VM"

ascii "  After the reboot, the VM is running the new image:"
ascii ""
ascii "   ┌───────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (rebooted into :demo-v2-chatbot-arm64)           │"
ascii "   │                                                           │"
ascii "   │  bootc status                                             │"
ascii "   │    booted:   :demo-v2-chatbot-arm64   ◄── NEW            │"
ascii "   │    rollback: :demo-v1-arm64           ◄── preserved      │"
ascii "   │                                                           │"
ascii "   │  curl http://localhost  →  web page still works          │"
ascii "   │  chatbot.service        →  running (Quadlet auto-start)  │"
ascii "   └───────────────────────────────────────────────────────────┘"
ascii ""
ascii "   Key point: the previous deployment is ALWAYS kept as rollback target."
ascii "   Nothing was lost — bootc maintains both deployments on disk."
echo ""
say "A workload change is delivered as a new image, not as manual host changes."
pause "Press ENTER to continue..."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── STEP 7 ────────────────────────────────────────────────────────────────────
step 7 "Deploy a deliberately broken version"

ascii "  Simulating a bad release — httpd is intentionally not enabled:"
ascii ""
ascii "   ┌──────────────────────┐  bootc switch          ┌────────────────────────┐"
ascii "   │ Quay                 │ ◄───────────────────── │  UTM VM                │"
ascii "   │ :demo-broken-arm64   │   pulls broken image    │                        │"
ascii "   └──────────────────────┘                        └────────────┬───────────┘"
ascii "                                                                │ systemctl reboot"
ascii "                                                                ▼"
ascii "                                                   ┌────────────────────────┐"
ascii "                                                   │  UTM VM (rebooted)     │"
ascii "                                                   │                        │"
ascii "                                                   │  httpd.service FAILED  │"
ascii "                                                   │  curl http://localhost │"
ascii "                                                   │    → connection refused │"
ascii "                                                   └────────────────────────┘"
ascii ""
ascii "   This is the demo's 'oh no' moment — sets up the rollback story."
echo ""
say "This version contains a known mistake: the HTTP service is not enabled."
say "The failure makes rollback visible and gives the audience a real recovery path."
pause "Press ENTER to continue..."
run remote sudo bootc switch "${IMAGE_BROKEN}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo systemctl --no-pager --full status httpd || true
run remote curl -fsS http://localhost | lynx -stdin -dump || true
run remote sudo bootc status
pause

# ── STEP 8 ────────────────────────────────────────────────────────────────────
step 8 "Rollback to the known-good deployment"

ascii "  One command, one reboot — back to a known-good state:"
ascii ""
ascii "   ┌────────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (running broken image)                            │"
ascii "   │                                                            │"
ascii "   │  sudo bootc rollback --apply                               │"
ascii "   │    → activates the previous deployment entry              │"
ascii "   │    → reboots into :demo-v2-chatbot-arm64                  │"
ascii "   └────────────────────────────────────────────────────────────┘"
ascii "                         │ reboot"
ascii "                         ▼"
ascii "   ┌────────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (rolled back)                                     │"
ascii "   │                                                            │"
ascii "   │  bootc status                                              │"
ascii "   │    booted:   :demo-v2-chatbot-arm64   ◄── restored        │"
ascii "   │    rollback: :demo-broken-arm64       ◄── (still there)   │"
ascii "   │                                                            │"
ascii "   │  curl http://localhost  →  working again                  │"
ascii "   └────────────────────────────────────────────────────────────┘"
ascii ""
ascii "   No reinstall. No Ansible. No SSH config surgery."
ascii "   bootc keeps both deployments — rollback is always one reboot away."
echo ""
say "bootc keeps the previous deployment as a rollback target."
pause "Press ENTER to continue..."
run remote sudo bootc rollback --apply || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── STEP 9 ────────────────────────────────────────────────────────────────────
step 9 "Deploy the fixed image"

ascii "  The fix is a new image version — built, tested, and promoted through CI:"
ascii ""
ascii "   ┌─────────────────┐  git commit+push  ┌──────────────────────────────┐"
ascii "   │ Containerfile   │ ────────────────► │ GitHub Actions               │"
ascii "   │ (httpd fix)     │                   │  build → sign → push         │"
ascii "   └─────────────────┘                   │  :demo-v3-fixed-arm64        │"
ascii "                                         └──────────────┬───────────────┘"
ascii "                                                        │ bootc switch"
ascii "                                                        ▼"
ascii "                                         ┌──────────────────────────────┐"
ascii "                                         │  UTM VM  (rebooted)          │"
ascii "                                         │                              │"
ascii "                                         │  httpd.service  ✔  running  │"
ascii "                                         │  curl http://localhost  ✔   │"
ascii "                                         └──────────────────────────────┘"
ascii ""
ascii "   Same OS lifecycle pattern: build once → test → deliver as image."
echo ""
say "The fix is built once, tested, and delivered as a new image version."
pause "Press ENTER to continue..."
run remote sudo bootc switch "${IMAGE_FIXED}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── STEP 10 ───────────────────────────────────────────────────────────────────
if [[ "${RUN_FLEET_EXTENSION}" == "1" ]]; then
  step 10 "One repository update, many VM deployments"

  ascii "  The same tested image applied to a fleet — demo-fleet-update-m5.sh:"
  ascii ""
  ascii "   ┌─────────────────────┐"
  ascii "   │ Quay                │"
  ascii "   │ :demo-v3-fixed-arm64│"
  ascii "   └──────────┬──────────┘"
  ascii "              │  for each VM in VM_TARGETS:"
  ascii "              │  ssh <target> sudo bootc switch <image>"
  ascii "              │"
  ascii "              ├──────────────► demo@192.168.64.20  (demo-web-01)"
  ascii "              ├──────────────► demo@192.168.64.21  (demo-web-02)"
  ascii "              ├──────────────► demo@192.168.64.22  (demo-web-03)"
  ascii "              └──────────────► demo@192.168.64.23  (demo-web-04)"
  ascii ""
  ascii "   FLEET_APPLY=${FLEET_APPLY}  →  $([ "${FLEET_APPLY}" == "1" ] && echo "LIVE: bootc switch runs on each VM" || echo "PLAN only: shows commands, no changes made")"
  ascii ""
  ascii "   After staging: reboot VMs in your change window to apply."
  ascii "   Every VM gets the identical, signed, tested image — no drift."
  echo ""
  say "The tested image can be applied to a fleet using the same target reference."
  note "Fleet: ${VM_TARGETS}"
  pause "Press ENTER to continue..."
  IMAGE_UPDATE="${IMAGE_FIXED}" VM_TARGETS="${VM_TARGETS}" FLEET_APPLY="${FLEET_APPLY}" \
    ./scripts/demo-fleet-update-m5.sh
  pause "Press ENTER to continue..."
fi

# ── STEP 11 (optional SNO) ────────────────────────────────────────────────────
if [[ "${RUN_SNO_EXTENSION}" == "1" ]]; then
  step 11 "Optional: the same model on OpenShift Virtualization"

  ascii "  The local demo used ARM64 in UTM; SNO runs the AMD64 image natively:"
  ascii ""
  ascii "   ┌─────────────────────┐  skopeo copy   ┌──────────────────────────┐"
  ascii "   │ Quay                │ ─────────────► │ Quay                     │"
  ascii "   │ :dev-disk-amd64     │  same digest   │ :prod-disk-amd64         │"
  ascii "   └─────────────────────┘                └─────────────┬────────────┘"
  ascii "                                                         │ CDI import"
  ascii "                                                         ▼"
  ascii "   ┌──────────────────────────────────────────────────────────────────┐"
  ascii "   │  OpenShift Virtualization (SNO x86_64)                           │"
  ascii "   │                                                                  │"
  ascii "   │  ansible-playbook provision-vm.yml                               │"
  ascii "   │    → Namespace, PullSecret, DataVolume, VirtualMachine           │"
  ascii "   │                                                                  │"
  ascii "   │  bootc status  (via virtctl ssh)                                 │"
  ascii "   │    booted: :prod-amd64                                           │"
  ascii "   └──────────────────────────────────────────────────────────────────┘"
  ascii ""
  ascii "   OpenShift manages the VM platform."
  ascii "   bootc manages the guest OS lifecycle — same pattern as UTM."
  echo ""
  say "The local demo used ARM64 in UTM; the SNO extension uses a prebuilt AMD64 image."
  say "OpenShift manages the VM platform while bootc manages the guest OS lifecycle."
  note "Show the prepared VirtualMachine, its DataVolume, and bootc status over SSH."
  pause
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
say "Cleaning up demo resources..."
run podman rm -f bootc-demo-test 2>/dev/null || true

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   Demo complete                                              ║"
echo "  ║                                                              ║"
echo "  ║   build → sign → promote → deploy → chatbot                 ║"
echo "  ║   → fail → rollback → fix → fleet                           ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
