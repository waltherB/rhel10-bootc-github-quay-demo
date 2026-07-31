#!/usr/bin/env bash
# ============================================================
#  RHEL 10 bootc Demo – presenter runner
#  Usage: ./scripts/demo-run.sh [START_STEP]
#
#  Each step prints a title + narration, then waits for ENTER.
#  Commands are shown in a distinct colour before running.
#  Press Ctrl-C at any time to abort.
#
#  To restart from a specific step, set START_STEP:
#    START_STEP=9a ./scripts/demo-run.sh
#  Valid step IDs: 1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b
#
#  ARCH SPLIT:
#    ARM64 bootc image + qcow2 disk are built LOCALLY (native on Mac),
#    used only for the local UTM VM demo (steps 2, 2b, 7b-8).
#    AMD64 bootc image + qcow2 disk are built REMOTELY by GitHub
#    Actions (native on ubuntu-latest runners), used only for
#    OpenShift Virtualization on the x86_64 SNO cluster (step 9a).
#    The two never cross paths — see scripts/demo-env.sh.example.
#
#  To pre-set variables, create scripts/demo-env.sh:
#    export IMAGE_ARM="quay.io/waba/bootc-guide:dev-arm64"
#    export IMAGE_AMD="quay.io/waba/bootc-guide:dev-amd64"
#    export DISK_IMAGE_ARM="quay.io/waba/bootc-guide:dev-disk-arm64"
#    export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:dev-disk-amd64"
#    export VM_SSH="demo@192.168.65.10"
#    export SNO_API="https://api.waba-sno.adc.lan"
#    export SNO_TOKEN="$(oc whoami -t)"
#    export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:prod-disk-amd64"  # skip rebuild
#  See scripts/demo-env.sh.example for the full variable set.
#  It will be sourced automatically if it exists.
# ============================================================
set -euo pipefail

# ── Source env file if present ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

# ── Colours ─────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'      # step headers
YELLOW='\033[1;33m'    # narration / talking points
GREEN='\033[1;32m'     # commands about to run
BLUE='\033[1;34m'      # informational notes
RED='\033[1;31m'       # warnings / manual actions needed
RESET='\033[0m'

# ── Config – defaults only used if env var is completely absent ──
: "${IMAGE_ARM:=quay.io/waba/bootc-guide:dev-arm64}"
: "${IMAGE_AMD:=quay.io/waba/bootc-guide:dev-amd64}"
: "${VM_SUDO_PASSWORD:=redhat}"
: "${VM_USER:=demo}"

# ── Helper to mask sensitive data ───────────────────────────
mask_value() {
  local val="$1"
  local len=${#val}
  
  # If the value is very short, just hide it completely
  if (( len <= 4 )); then
    echo "****"
  else
    # Shows first 3 chars, asterisks for the middle, and last 3 chars
    echo "${val:0:3}****${val: -3}"
  fi
}


# ── Prompt for any required variable, confirming pre-set values ─
prompt_var() {
  local var="$1"
  local prompt="$2"
  local default="${3:-}"
  local current
  local display_value

  current="$(printenv "$var" 2>/dev/null || true)"

  if [[ -n "${current}" ]]; then

    # Mask sensitive variables
    case "$var" in
      *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*ORG*|*B64*)
        display_value="$(mask_value "$current")"
        ;;
      *)
        display_value="$current"
        ;;
    esac

    echo -e "${BOLD}  ${prompt}${RESET}"
    echo -e "${BLUE}  Current: ${display_value}${RESET}"
    echo -e "${BOLD}  Press ENTER to confirm, or type a new value: ${RESET}"

    read -r input

    if [[ -n "${input}" ]]; then
      export "$var"="${input}"
    else
      export "$var"="${current}"
    fi

  elif [[ -n "${default}" ]]; then

    echo -e "${BOLD}  ${prompt}${RESET}"
    echo -e "${BLUE}  Default: ${default}${RESET}"
    echo -e "${BOLD}  Press ENTER to accept, or type a new value: ${RESET}"

    read -r input
    export "$var"="${input:-${default}}"

  else

    echo -e "${BOLD}  ${prompt}${RESET}"
    read -r input
    export "$var"="${input}"

  fi
}


# ── Step-skip logic ─────────────────────────────────────────
# START_STEP can be set to any step ID (e.g. "9a") to skip earlier steps.
# Steps are ordered in STEP_ORDER; once we reach START_STEP we flip
# _STEP_REACHED=1 and every subsequent step runs normally.

STEP_ORDER=(1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b)
_STEP_REACHED=0

step_index() {
  local target="$1"
  local idx=0
  local step
  for step in "${STEP_ORDER[@]}"; do
    if [[ "${step}" == "${target}" ]]; then
      echo "${idx}"
      return 0
    fi
    ((idx++))
  done
  echo "-1"
}

# Call at the top of each step block. Returns 0 (run) or 1 (skip).
should_run() {
  local id="$1"
  local start_step="${START_STEP:-}"
  local current_index target_index

  if [[ -z "${start_step}" || "${_STEP_REACHED}" -eq 1 ]]; then
    _STEP_REACHED=1
    return 0
  fi

  current_index="$(step_index "${id}")"
  target_index="$(step_index "${start_step}")"

  if [[ "${current_index}" == "-1" ]]; then
    echo -e "${RED}  ⚠  Unknown step ID ${id}; running it${RESET}"
    _STEP_REACHED=1
    return 0
  fi

  if [[ "${target_index}" == "-1" ]]; then
    echo -e "${RED}  ⚠  Unknown START_STEP=${start_step}; running from the beginning${RESET}"
    _STEP_REACHED=1
    return 0
  fi

  if [[ "${current_index}" -ge "${target_index}" ]]; then
    _STEP_REACHED=1
    return 0
  fi

  echo -e "${BLUE}  ⏭  Skipping step ${id} (START_STEP=${START_STEP})${RESET}"
  return 1
}

# ── Helpers ─────────────────────────────────────────────────

# Print a step banner and wait for ENTER
step() {
  local number="$1"
  local title="$2"
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  STEP ${number}: ${title}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

# Print narration bullet points (talking points for the presenter)
narrate() {
  echo -e "${YELLOW}  ▶  $*${RESET}"
}

# Print ASCII Flow Diagram in Cyan
ascii() {
  echo -e "${CYAN}$*${RESET}"
}

# Print and run a command
run() {
  local cmd="$*"
  # Mask sensitive tokens/passwords in the display string
  local masked_cmd
  masked_cmd=$(echo "$cmd" | sed -E \
    -e 's/(--token=|--password=|--secret=|--key=)[^ ]+/\1********/g' \
    -e 's/(ssh_pub_key=")[^"]+/\1********/g')

  echo ""
  echo -e "${GREEN}  \$ $masked_cmd${RESET}"
  echo ""
  eval "$@"
}

# Pause and wait for ENTER
pause() {
  local msg="${1:-Press ENTER to continue...}"
  echo ""
  echo -e "${BOLD}  ↩  ${msg}${RESET}"
  read -r
}

# Print a manual action the presenter needs to do (no automation)
manual() {
  echo ""
  echo -e "${RED}  ★  MANUAL: $*${RESET}"
  echo ""
}

# Print an info note
note() {
  echo -e "${BLUE}  ℹ  $*${RESET}"
}

validate_image_for_openshift() {
  local image="$1"
  local authfile=""

  if [[ -n "${QUAY_DOCKER_CONFIG_B64:-}" ]]; then
    authfile="$(mktemp)"
    echo "${QUAY_DOCKER_CONFIG_B64}" | base64 --decode > "${authfile}"
  fi

  echo ""
  echo -e "${BLUE}  Validating OpenShift VM image: ${image}${RESET}"
  if ! command -v skopeo &>/dev/null; then
    echo -e "${RED}  ERROR: skopeo is required to validate the image.${RESET}"
    [[ -n "${authfile}" ]] && rm -f "${authfile}"
    exit 1
  fi

  if [[ -n "${authfile}" ]]; then
    skopeo inspect --authfile "${authfile}" "docker://${image}" >/dev/null 2>&1
  else
    skopeo inspect "docker://${image}" >/dev/null 2>&1
  fi
  local rc=$?

  [[ -n "${authfile}" ]] && rm -f "${authfile}"

  if [[ ${rc} -ne 0 ]]; then
    echo -e "${RED}  ERROR: Image ${image} is not accessible or not valid for provisioning.${RESET}"
    echo -e "${RED}  Check Quay auth and image name, or use a different IMAGE value.${RESET}"
    exit 1
  fi

  echo -e "${BLUE}  Image ${image} is available for provisioning.${RESET}"
}

# ── Demo starts here ─────────────────────────────────────────

clear
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   RHEL 10 Image Mode Demo                        ║"
echo "  ║   GitHub Actions · Quay · OpenShift Virt         ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Collect any missing variables interactively before the demo starts
echo -e "${BOLD}  Checking required variables...${RESET}"
echo ""

if [[ -n "${START_STEP:-}" ]]; then
  echo -e "${YELLOW}  ⏩  START_STEP=${START_STEP} — will skip steps before '${START_STEP}'${RESET}"
  echo ""
fi

prompt_var IMAGE_ARM   "  Local ARM64 bootc image (Mac / UTM VM): " "quay.io/waba/bootc-guide:dev-arm64"
prompt_var IMAGE_AMD   "  Remote AMD64 bootc image (GitHub CI / OpenShift): " "quay.io/waba/bootc-guide:dev-amd64"
prompt_var VM_SSH      "  UTM VM SSH target (e.g. demo@192.168.65.10) — check 'arp -a': "
prompt_var VM_SSH_KEY  "  SSH private key for VM access: " "${HOME}/.ssh/id_ed25519"
prompt_var VM_USER    "  SSH username for the VM: " "${VM_USER:-demo}"
prompt_var SNO_API     "  SNO API URL (e.g. https://api.your-cluster.example.com): "

# SNO_TOKEN — auto-fetch from oc if already logged in, otherwise prompt
if [[ -z "$(printenv SNO_TOKEN 2>/dev/null || true)" ]]; then
  if command -v oc &>/dev/null; then
    AUTO_TOKEN="$(oc whoami -t 2>/dev/null || true)"
    if [[ -n "${AUTO_TOKEN}" ]]; then
      echo -e "${BLUE}  SNO_TOKEN: auto-fetched via 'oc whoami -t'${RESET}"
      export SNO_TOKEN="${AUTO_TOKEN}"
    fi
  fi
fi
prompt_var SNO_TOKEN   "  SNO login token (press ENTER to use current oc session): "

if [[ -z "${QUAY_DOCKER_CONFIG_B64:-}" ]]; then
  # Podman stores auth in ~/.config/containers/auth.json on macOS
  AUTH_FILE="${HOME}/.config/containers/auth.json"
  if [[ ! -f "${AUTH_FILE}" ]]; then
    AUTH_FILE="${HOME}/.docker/config.json"  # fallback for Docker users
  fi
  if [[ ! -f "${AUTH_FILE}" ]]; then
    echo -e "${RED}  ERROR: No container auth file found. Run: podman login quay.io${RESET}"
    exit 1
  fi
  echo -e "${BOLD}  QUAY_DOCKER_CONFIG_B64 not set — generating from ${AUTH_FILE}...${RESET}"
  export QUAY_DOCKER_CONFIG_B64
  QUAY_DOCKER_CONFIG_B64="$(base64 < "${AUTH_FILE}")"
fi

echo ""
note "IMAGE_ARM = ${IMAGE_ARM}   (local, UTM VM)"
note "IMAGE_AMD = ${IMAGE_AMD}   (GitHub CI, OpenShift Virt)"
note "VM SSH    = ${VM_SSH}"
note "VM USER   = ${VM_USER}"
note "VM SSH KEY      = $(mask_value "$VM_SSH_KEY")"
note "SNO API   = ${SNO_API}"
note "SNO TOKEN = ${SNO_TOKEN:0:8}…  (truncated)"
# DISK_IMAGE_AMD is derived at step 9a from IMAGE_AMD if not pre-set
note "DISK_IMAGE_AMD= ${DISK_IMAGE_AMD:-"(auto: ${IMAGE_AMD%:*}:${IMAGE_AMD##*:}-disk)"}"
echo ""
if [[ ! -f "${VM_SSH_KEY}" ]]; then
  echo -e "${RED}  ERROR: SSH key ${VM_SSH_KEY} not found. Create or specify a valid private key.${RESET}"
  exit 1
fi
SSH_OPTIONS="-i '${VM_SSH_KEY}' -o BatchMode=yes -o StrictHostKeyChecking=no"
pause "Press ENTER to start the demo..."

# ────────────────────────────────────────────────────────────
step "1" "Show the repo structure"
# ────────────────────────────────────────────────────────────
if should_run "1"; then
  narrate "Single git repo drives the entire OS lifecycle"
  narrate "Containerfile defines the OS image declaratively"
  narrate "GitHub Actions builds, tests, signs, and pushes to Quay"
  narrate "Ansible provisions VMs on OpenShift Virtualization"
  echo ""
  run ls -1
  echo ""
  run cat Containerfile
  pause
fi

# ────────────────────────────────────────────────────────────
step "2" "Local build on Mac M4"
# ────────────────────────────────────────────────────────────
if should_run "2"; then
  ascii "  ┌──────────────┐   podman build (arm64)   ┌─────────────────────┐"
  ascii "  │ Containerfile│ ───────────────────────► │ Local Container OS  │"
  ascii "  └──────────────┘                          │ (:dev-arm64)        │"
  ascii "                                            └─────────────────────┘"
  echo ""
  narrate "Build the bootc image locally for arm64 (native on M4)"
  narrate "TARGET_PLATFORM_LOCAL is linux/arm64 – no cross-compilation, no emulation"
  echo ""

  # Step 2 always builds natively for arm64 on this Mac, tagged :dev-arm64.
  # This is entirely separate from the amd64 image (Step 4/5, built by
  # GitHub Actions), which is what OpenShift Virt ultimately runs.
  # Deliberately NOT reusing a shared PLATFORM var: mixing the two up is
  # exactly what caused a mislabeled arm64 disk to reach OpenShift before.
  note "IMAGE_ARM=${IMAGE_ARM}  TARGET_PLATFORM_LOCAL=${TARGET_PLATFORM_LOCAL:-linux/arm64}"
  pause "Press ENTER to start local build..."
  run "IMAGE_ARM=${IMAGE_ARM} TARGET_PLATFORM_LOCAL=${TARGET_PLATFORM_LOCAL:-linux/arm64} ./scripts/local-build.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "2b" "Build ARM64 qcow2 disk image locally (for UTM VM)"
# ────────────────────────────────────────────────────────────
if should_run "2b"; then
  ascii "  ┌────────────────────┐  bootc-image-builder   ┌─────────────────┐"
  ascii "  │ Local Container OS │ ─────────────────────► │ disk.qcow2      │"
  ascii "  │ (:dev-arm64)       │      (arm64)           │ (for UTM VM)    │"
  ascii "  └────────────────────┘                        └─────────────────┘"
  echo ""
  narrate "bootc-image-builder runs natively arm64-on-arm64 here — no emulation"
  narrate "This qcow2 is only ever used to (re)provision the local UTM VM,"
  narrate "never OpenShift — that always gets the amd64 disk from GitHub Actions"
  note "IMAGE_ARM=${IMAGE_ARM}  DISK_IMAGE_ARM=${DISK_IMAGE_ARM:-"${IMAGE_ARM%:*}:dev-disk-arm64"}"
  pause "Press ENTER to build and push the ARM64 qcow2..."
  run "IMAGE_ARM=${IMAGE_ARM} DISK_IMAGE_ARM=${DISK_IMAGE_ARM:-"${IMAGE_ARM%:*}:dev-disk-arm64"} ./scripts/local-build-qcow2.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "3" "Smoke test the image as a container"
# ────────────────────────────────────────────────────────────
if should_run "3"; then
  ascii "  ┌────────────────────┐   podman run --rm -p   ┌─────────────────┐"
  ascii "  │ Local Container OS │ ─────────────────────► │ Smoke Test      │"
  ascii "  │ (:dev-arm64)       │                        │ (HTTP / MOTD)   │"
  ascii "  └────────────────────┘                        └─────────────────┘"
  echo ""
  narrate "Run the image as a plain container first – fast feedback before touching a VM"
  narrate "Check the web page and the motd are baked in"
  pause "Press ENTER to run smoke test..."
  run "IMAGE=${IMAGE_ARM} ./scripts/local-test.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "4" "Push and sign the image"
# ────────────────────────────────────────────────────────────
if should_run "4"; then
  ascii "  ┌────────────────────┐   podman push / cosign   ┌────────────────┐"
  ascii "  │ Local Container OS │ ───────────────────────► │ Quay Registry  │"
  ascii "  └────────────────────┘                          │ (:dev-arm64)   │"
  ascii "                                                  └────────────────┘"
  ascii "  ┌────────────────────┐   git push / dispatch    ┌────────────────┐"
  ascii "  │ Git Source Commit  │ ───────────────────────► │ GitHub Actions │"
  ascii "  └────────────────────┘                          │ (AMD64 Build)  │"
  ascii "                                                  └────────────────┘"
  echo ""
  narrate "Push :dev-arm64 to Quay.io (local ARM64 image, for the UTM VM)"
  narrate "Sign with keyless Cosign (OIDC – no long-lived key material)"
  pause "Press ENTER to push and sign..."
  run "IMAGE_ARM=${IMAGE_ARM} ./scripts/local-push.sh"
  run "IMAGE=${IMAGE_ARM} ./scripts/local-sign-keyless.sh"

narrate "Pushing current git changes to main to trigger GitHub Actions CI..."
narrate "CI builds both :dev-amd64 and its containerDisk (:dev-disk-amd64) sequentially."

# Use git status to safely check for any working tree changes (staged, unstaged, or untracked)
if [ -n "$(git status --porcelain)" ]; then
  note "Local changes detected. Committing and pushing..."
  run git commit -a -m "\"chore: push presentation progress to trigger CI\""
  run git push
else
  note "No local changes detected."

  # Append '|| true' so git log failure doesn't crash scripts running under set -e
  LOCAL_COMMITS=$(git log origin/main..HEAD 2>/dev/null || true)
  
  if [ -n "$LOCAL_COMMITS" ]; then
      note "Local commits exist. Pushing..."
      run git push
  else
      note "No new commits to push. Making a change to files/motd to trigger CI..."
            
      # Update the motd with timestamp
      MOTD_VERSION="v1-$(date +%F-%H%M%S)"
      echo "RHEL 10 Image Mode Demo ${MOTD_VERSION}" > files/motd
      
      note "Updated files/motd to: ${MOTD_VERSION}"
      run cat files/motd
      
      # Check if git is initialized and has a remote
      if ! git remote -v | grep -q origin; then
          note "No git remote configured. Skipping commit/push."
      else
          # Stage and commit the change
          run git add files/motd
          run git commit -m "\"chore: bump motd to ${MOTD_VERSION} to trigger CI\""
          run git push
      fi
  fi
fi
fi
# ────────────────────────────────────────────────────────────
step "5" "GitHub Actions CI pipeline"
# ────────────────────────────────────────────────────────────
if should_run "5"; then
  ascii "  ┌──────────────────┐   Build / Sign / Push   ┌──────────────────┐"
  ascii "  │ GitHub Runner    │ ──────────────────────► │ Quay Registry    │"
  ascii "  │ (ubuntu-latest)  │   (native amd64)        │ (:dev-amd64 &    │"
  ascii "  │                  │                         │  :dev-disk-amd64)│"
  ascii "  └──────────────────┘                         └──────────────────┘"
  echo ""
  narrate "Every push to main triggers: build OS image → build qcow2 → build containerDisk → push both to Quay"
  manual "Open GitHub → Actions → 'Build, Sign, and Push bootc (AMD64 & ARM64)' and show the running workflow"
  manual "Point out: build job, storage config, Quay push, Cosign sign, and the containerDisk push"
  note "The single consolidated pipeline avoids any race conditions or duplicate builds."
  pause "Press ENTER once the workflow is green..."
fi

# ────────────────────────────────────────────────────────────
step "6" "Promote :dev → :prod"
# ────────────────────────────────────────────────────────────
if should_run "6"; then
  ascii "  ┌──────────────────┐       skopeo copy       ┌──────────────────┐"
  ascii "  │ Quay: :dev-amd64 │ ──────────────────────► │ Quay: :prod-amd64│"
  ascii "  └──────────────────┘    (Same SHA digest)    └──────────────────┘"
  echo ""
  narrate "The promote workflow uses skopeo copy – same digest, just a new tag"
  narrate "No rebuild – what was tested is exactly what goes to prod"
  manual "Open GitHub → Actions → promote-rhel10-bootc-prod → Run workflow (source_tag: dev)"
  pause "Press ENTER once :prod is promoted..."
fi

# ────────────────────────────────────────────────────────────
step "7a" "Make a visible change to trigger a live update demo"
# ────────────────────────────────────────────────────────────
if should_run "7a"; then
  ascii "  ┌──────────────────┐    git commit & push    ┌──────────────────┐"
  ascii "  │ Update files/motd│ ──────────────────────► │ GitHub Actions   │"
  ascii "  │ (Version bump)   │                         │ (Rebuild & Push) │"
  ascii "  └──────────────────┘                         └──────────────────┘"
  echo ""
  narrate "Change the motd so the update is obvious on the VM after reboot"
  pause "Press ENTER to write the new motd and push..."
  MOTD_VERSION="v2-$(date +%F-%H%M)"
  run "echo 'RHEL 10 Image Mode Demo ${MOTD_VERSION}' > files/motd"
  run cat files/motd
  run git add files/motd
  run git diff --cached -- files/motd
  run git commit -m "\"chore: bump motd to ${MOTD_VERSION} for live update demo\""
  run git push
  narrate "CI is now building the new image – go to GitHub Actions to show it"
  manual "Open GitHub → Actions and watch the new build run"
  manual "Open GitHub → Actions → promote-rhel10-bootc-prod → Run workflow (source_tag: dev)"
  pause "Press ENTER once the new :dev is built and promoted to :prod..."
fi

# ────────────────────────────────────────────────────────────
step "7b" "Check current VM state (before update)"
# ────────────────────────────────────────────────────────────
if should_run "7b"; then
  ascii "  ┌──────────────────┐     ssh vm-status       ┌────────────────────┐"
  ascii "  │ Local Workstation│ ──────────────────────► │ UTM Virtual Machine│"
  ascii "  └──────────────────┘                         │ (Captures Digest). │"
  ascii "                                               └────────────────────┘"
  echo ""
  narrate "SSH into the UTM VM and capture the current booted digest"
  narrate "vm-status is baked into the image – available everywhere this OS runs"
  note "Connecting to ${VM_SSH}"
  pause "Press ENTER to check VM status..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "7c" "Pull and apply the update on the VM"
# ────────────────────────────────────────────────────────────
if should_run "7c"; then
  ascii "  ┌──────────────────┐    ssh vm-upgrade       ┌─────────────────────┐"
  ascii "  │ Quay Registry    │ ◄────────────────────── │ UTM Virtual Machine │"
  ascii "  │ (:prod-arm64)    │   (bootc upgrade)       │ (Staged & Reboot)   │"
  ascii "  └──────────────────┘                         └─────────────────────┘"
  echo ""
  narrate "bootc upgrade pulls the new :dev layers and stages them"
  narrate "The running OS is untouched until reboot – atomic, safe rollback point preserved"
  pause "Press ENTER to trigger vm-upgrade (will reboot the VM)..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-upgrade || true
  note "VM is rebooting – waiting 30 seconds..."
  sleep 30
  pause "Press ENTER once the VM is back up (check UTM console if needed)..."
fi

# ────────────────────────────────────────────────────────────
step "7d" "Verify the update on the VM"
# ────────────────────────────────────────────────────────────
if should_run "7d"; then
  ascii "  ┌──────────────────┐     ssh vm-status       ┌─────────────────────┐"
  ascii "  │ Local Workstation│ ──────────────────────► │ UTM Virtual Machine │"
  ascii "  └──────────────────┘                         │ (Verify v2 Digest)  │"
  ascii "                                               └─────────────────────┘"
  echo ""
  narrate "New digest should differ from what we saw in step 7b"
  narrate "motd should now show v2"
  pause "Press ENTER to verify..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "8" "Rollback"
# ────────────────────────────────────────────────────────────
if should_run "8"; then
  ascii "  ┌──────────────────┐  sudo bootc rollback    ┌─────────────────────┐"
  ascii "  │ Local Workstation│ ──────────────────────► │ UTM Virtual Machine │ "
  ascii "  └──────────────────┘                         │ (Reverts & Reboot). │"
  ascii "                                               └─────────────────────┘"
  echo ""
  narrate "bootc keeps the previous deployment – rollback is instant, no reinstall"
  narrate "One command, one reboot – back to the exact previous image"
  pause "Press ENTER to trigger rollback..."
  note "A sudo password prompt will appear inside the SSH session. Enter the VM sudo password when requested."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" "sudo bootc rollback" || true
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" "sudo systemctl reboot" || true
  note "VM is rebooting after rollback – waiting 30 seconds..."
  sleep 30
  pause "Press ENTER once the VM is back up..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "9a" "OpenShift Virtualization – build disk image & provision VM"
# ────────────────────────────────────────────────────────────
if should_run "9a"; then
  ascii "  ┌────────────────────┐   skopeo promote    ┌─────────────────────┐"
  ascii "  │ Quay: dev-disk-amd │ ──────────────────► │ Quay: prod-disk-amd │"
  ascii "  └────────────────────┘                     └─────────────────────┘"
  ascii "                                                        │ CDI Pull"
  ascii "  ┌────────────────────┐   Ansible Playbook  ┌──────────▼──────────┐"
  ascii "  │ OpenShift Cluster  │ ◄────────────────── │ KubeVirt / Virt VM  │"
  ascii "  │ (SNO x86_64)       │                     │ (provision-vm.yml)  │"
  ascii "  └────────────────────┘                     └─────────────────────┘"
  echo ""
  narrate "Same OS, now running as a KubeVirt VirtualMachine on SNO"
  narrate "We built :dev-disk-amd64 at step 4 — now we promote it to :prod-disk-amd64 (same digest, new tag)"
  narrate "CDI pulls :prod-disk-amd64 directly from Quay — no HTTP server needed"
  narrate "Only the AMD64 disk is ever used here — the x86_64 SNO cluster can't run arm64 anyway"
  note "Logging in to SNO cluster: ${SNO_API}"
  if [[ -n "${SNO_TOKEN}" ]]; then
    run oc login "${SNO_API}" --token="${SNO_TOKEN}" --insecure-skip-tls-verify
  else
    manual "Run: oc login ${SNO_API} --token=<your-token> --insecure-skip-tls-verify"
    pause "Press ENTER once logged in to SNO..."
  fi

  # Derive PROD_IMAGE_AMD / PROD_DISK_IMAGE_AMD from IMAGE_AMD base
  _BASE="${IMAGE_AMD%:*}"
  PROD_IMAGE_AMD="${PROD_IMAGE_AMD:-${_BASE}:prod-amd64}"
  SOURCE_DISK_AMD="${DISK_IMAGE_AMD:-${_BASE}:dev-disk-amd64}"
  PROD_DISK_IMAGE_AMD="${PROD_DISK_IMAGE_AMD:-${_BASE}:prod-disk-amd64}"
  note "PROD_IMAGE_AMD      = ${PROD_IMAGE_AMD}"
  note "PROD_DISK_IMAGE_AMD = ${PROD_DISK_IMAGE_AMD}  (containerDisk for CDI)"

  # ── 9a-i: Promote :dev-disk-amd64 → :prod-disk-amd64 ───────
  until skopeo inspect docker://$DISK_IMAGE_AMD >/dev/null 2>&1
  do
    echo "Waiting for $DISK_IMAGE_AMD..."
    sleep 15
  done
  narrate "Step 9a-i: promote :dev-disk-amd64 → :prod-disk-amd64 via skopeo copy (same digest, new tag)"
  narrate "Mirrors the OS image promote: :dev-amd64 → :prod-amd64 — no rebuild, what was tested is what runs"
  pause "Press ENTER to promote :dev-disk-amd64 → :prod-disk-amd64..."
  run SOURCE_DISK="${SOURCE_DISK_AMD}" TARGET_DISK="${PROD_DISK_IMAGE_AMD}" ./scripts/local-promote-disk.sh

  # ── 9a-ii: Provision the VM via Ansible ─────────────────
  narrate "Step 9a-ii: Ansible creates Namespace, PullSecret, DataVolume and VirtualMachine"
  pause "Press ENTER to run the Ansible provisioning playbook..."
  run ansible-playbook ansible/provision-vm.yml \
    -e "disk_image=${PROD_DISK_IMAGE_AMD}" \
    -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'REPLACE_KEY')\""
  manual "Open OpenShift console → Virtualization → VirtualMachines and show the VM starting"
  pause
fi

# ────────────────────────────────────────────────────────────
step "9b" "OpenShift Virtualization – upgrade VM with Ansible"
# ────────────────────────────────────────────────────────────
if should_run "9b"; then
  ascii "  ┌────────────────────┐   Ansible Playbook  ┌─────────────────────┐"
  ascii "  │ upgrade-vm.yml     │ ──────────────────► │ virtctl SSH / bootc │"
  ascii "  └────────────────────┘                     │ (Automated Upgrade) │"
  ascii "                                             └─────────────────────┘"
  echo ""
  narrate "Same bootc upgrade loop, now orchestrated by Ansible via virtctl SSH"
  narrate "Check before, upgrade, reboot, verify – fully automated"
  pause "Press ENTER to run the Ansible upgrade playbook..."
  run ansible-playbook ansible/upgrade-vm.yml
  pause
fi

# ────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   Demo complete!                                 ║"
echo "  ║                                                  ║"
echo "  ║   Repo: github.com/waba/rhel10-bootc-…           ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"
