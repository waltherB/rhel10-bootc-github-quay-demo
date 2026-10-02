#!/usr/bin/env bash
# ============================================================
#  Reset the demo VM disk back to the clean IMAGE_GOOD baseline.
#
#  Problem: After running demo-run-m5.sh (which runs multiple
#  `bootc switch` + reboot cycles), the VM disk accumulates
#  old deployments. The qcow2 grows and rollback state is
#  left behind, causing the next demo run to start in an
#  inconsistent state.
#
#  This script:
#    1. Stops the running demo VM (QEMU process from create-main-vm.sh)
#    2. Copies a fresh output/qcow2/disk-arm.qcow2 back to the
#       working disk location
#    3. Resets the EFI vars to the clean template
#    4. Restarts the VM
#
#  Run BEFORE each demo session:
#    ./scripts/local-reset-utm-vm.sh
#
#  Or to just reset without restarting:
#    RESTART_VM=0 ./scripts/local-reset-utm-vm.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${RESTART_VM:=1}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"

# Paths - must match create-main-vm.sh
SOURCE_DISK="${REPO_DIR}/output/qcow2/disk-arm.qcow2"
EFI_CODE="${QEMU_EFI_CODE:-/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"
EFI_VARS_TEMPLATE="${QEMU_EFI_VARS_TEMPLATE:-${HOME}/.config/qemu/demo-bootc-arm64-vars.fd}"

# Determine if this is a UTM-managed VM or a standalone QEMU VM
UTM_DISK="/Users/waba/Library/Containers/com.utmapp.UTM/Data/Documents/bootc-vm-arm64.utm/Data/disk-arm.qcow2"
QEMU_WORK_DISK="${REPO_DIR}/output/qcow2/disk-work.qcow2"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

note() { echo -e "${CYAN}  ℹ  $*${RESET}"; }
ok()   { echo -e "${GREEN}  ✓  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
die()  { echo -e "${RED}  ✗  $*${RESET}" >&2; exit 1; }

# ── Verify base disk exists ──────────────────────────────────
if [[ ! -f "${SOURCE_DISK}" ]]; then
  die "Base disk not found: ${SOURCE_DISK}
  Run: ./scripts/prepare-demo-m5.sh (or BUILD_UTM_DISK=1 ./scripts/prepare-demo-m5.sh)"
fi

note "Source disk: ${SOURCE_DISK} ($(du -sh "${SOURCE_DISK}" | cut -f1))"

# ── Check if IMAGE_GOOD matches the disk ────────────────────
MANIFEST="${REPO_DIR}/output/manifest-qcow2.json"
if [[ -s "${MANIFEST}" ]] && command -v jq &>/dev/null; then
  DISK_IMAGE_ID="$(jq -r '[.pipelines[].stages[]? |
    select(.type == "org.osbuild.container-deploy") |
    .inputs.images.references | keys[]][0] // empty' "${MANIFEST}")"
  if [[ -n "${DISK_IMAGE_ID:-}" ]]; then
    CURRENT_IMAGE_ID="$(podman image inspect --format '{{.Id}}' "${IMAGE_GOOD:-quay.io/waba/bootc-guide:demo-v1-arm64}" 2>/dev/null || true)"
    if [[ "${DISK_IMAGE_ID#sha256:}" != "${CURRENT_IMAGE_ID#sha256:}" ]]; then
      warn "Disk was built from ${DISK_IMAGE_ID} but ${IMAGE_GOOD:-IMAGE_GOOD} resolves to ${CURRENT_IMAGE_ID}."
      warn "Child images (v2, broken, v3) were built FROM ${IMAGE_GOOD:-IMAGE_GOOD}."
      warn "You should run: prepare-demo-m5.sh BUILD_UTM_DISK=1 to rebuild everything consistently."
      warn "Continuing reset anyway (the switch will still work if Quay images match the local build)."
    else
      ok "Disk is consistent with ${IMAGE_GOOD:-IMAGE_GOOD} (${CURRENT_IMAGE_ID::16}...)"
    fi
  fi
fi

# ── Stop any running demo QEMU process ──────────────────────
DEMO_PIDS="$(pgrep -f "bootc-vm-arm64\|disk-arm.qcow2\|disk-work.qcow2" 2>/dev/null || true)"
if [[ -n "${DEMO_PIDS}" ]]; then
  note "Stopping demo QEMU process(es): ${DEMO_PIDS}"
  # Send SIGTERM first, wait up to 10s, then SIGKILL
  kill "${DEMO_PIDS}" 2>/dev/null || true
  for _ in $(seq 1 10); do
    sleep 1
    if ! kill -0 ${DEMO_PIDS} 2>/dev/null; then break; fi
  done
  kill -9 ${DEMO_PIDS} 2>/dev/null || true
  sleep 1
  ok "QEMU process stopped."
else
  note "No running demo QEMU process found."
fi

# Also check if UTM is using this VM (UTM-managed QEMU process)
UTM_PIDS="$(pgrep -f "bootc-vm-arm64.utm" 2>/dev/null || true)"
if [[ -n "${UTM_PIDS}" ]]; then
  warn "UTM is managing the bootc VM. The UTM disk will be reset, but UTM itself must be stopped first."
  warn "Please close the VM in UTM, then re-run this script."
  warn "  UTM PID(s): ${UTM_PIDS}"
  warn "After reset, start the VM with: ./scripts/create-main-vm.sh"
  # Don't exit - still try to reset if possible
fi

# ── Reset UTM-managed disk if accessible ────────────────────
if [[ -f "${UTM_DISK}" ]]; then
  note "UTM disk found at: ${UTM_DISK}"
  if qemu-img info "${UTM_DISK}" &>/dev/null; then
    note "Resetting UTM disk from fresh qcow2..."
    cp -f "${SOURCE_DISK}" "${UTM_DISK}"
    ok "UTM disk reset: $(du -sh "${UTM_DISK}" | cut -f1)"
  else
    warn "UTM disk is locked (VM may still be running in UTM). Skipping UTM disk reset."
    warn "Stop the VM in UTM first, then run this script again."
  fi
fi

# ── Reset the working overlay disk ─────────────────────────
note "Resetting working disk: ${QEMU_WORK_DISK}"
cp -f "${SOURCE_DISK}" "${QEMU_WORK_DISK}"
ok "Working disk reset: $(du -sh "${QEMU_WORK_DISK}" | cut -f1)"

# ── Reset EFI vars ──────────────────────────────────────────
if [[ -f "${EFI_CODE}" ]]; then
  note "Resetting EFI vars template from: ${EFI_CODE}"
  mkdir -p "$(dirname "${EFI_VARS_TEMPLATE}")"
  cp -f "${EFI_CODE}" "${EFI_VARS_TEMPLATE}"
  ok "EFI vars reset."
else
  warn "EFI firmware not found at ${EFI_CODE}; EFI vars not reset."
fi

# ── Restart VM ──────────────────────────────────────────────
if [[ "${RESTART_VM}" == "1" ]]; then
  note "Restarting the demo VM..."
  echo ""
  echo "  Starting VM with QEMU (using the reset disk)."
  echo "  The VM will get an IP on the vmnet-shared network."
  echo "  VM_SSH target: ${VM_SSH:-demo@192.168.64.18}"
  echo ""
  "${SCRIPT_DIR}/create-main-vm.sh" &
  QEMU_BG_PID=$!
  echo ""
  note "VM started (PID ${QEMU_BG_PID}). Waiting 30s for network..."
  sleep 30
  VM_HOST="${VM_SSH:-demo@192.168.64.18}"
  if ssh -i "${VM_SSH_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 "${VM_HOST}" 'sudo bootc status' >/dev/null 2>&1; then
    ok "VM is up at ${VM_HOST} and bootc is responding."
  else
    warn "VM may not be ready yet at ${VM_HOST}. Give it another minute and check manually:"
    warn "  ssh -i ${VM_SSH_KEY} ${VM_HOST} 'sudo bootc status'"
  fi
fi

echo ""
ok "Reset complete. The VM disk is clean with just IMAGE_GOOD (demo-v1-arm64)."
echo ""
