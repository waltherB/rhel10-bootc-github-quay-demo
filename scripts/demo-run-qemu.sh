#!/usr/bin/env bash
# ============================================================
#  demo-run-qemu.sh — run the full M5 demo using QEMU instead of UTM
#
#  Starts a QEMU ARM64 main VM plus optional fleet VMs on the
#  192.168.64.0/24 subnet, discovers their IPs, then hands off
#  to demo-run-m5.sh for the interactive demo flow (steps 1–10,
#  skipping OCP-Virt step 11).
#
#  All VMs are torn down automatically on exit.
#
#  Usage:
#    ./scripts/demo-run-qemu.sh                  # full interactive demo
#    DEMO_AUTO=1 ./scripts/demo-run-qemu.sh      # skip all pause prompts
#    DEMO_AUTO=1 START_STEP=4 ./scripts/demo-run-qemu.sh  # start at step 4
#
#  Key overrides (all optional, loaded from demo-env.sh first):
#    QEMU_DISK            base qcow2 (default: output/qcow2/disk-arm.qcow2)
#    QEMU_MEMORY          main VM RAM in MB (default: 3072)
#    QEMU_FLEET_MEMORY    fleet VM RAM in MB (default: 2048)
#    QEMU_CPUS            vCPUs per VM (default: 2)
#    QEMU_BOOT_TIMEOUT    seconds to wait for IP (default: 180)
#    FLEET_SIZE           number of fleet VMs to start (default: 4)
#    RUN_CHATBOT_EXTENSION  1 = run chatbot steps 4+5 (default: 1)
#    RUN_FLEET_EXTENSION    1 = run fleet step 10 (default: 1)
#    RUN_SNO_EXTENSION      always 0 here (no OCP-Virt infra)
#    DEMO_AUTO            1 = auto-advance all pause prompts
#    START_STEP           step to start from (passed to demo-run-m5.sh)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QEMU_DISK:=${REPO_DIR}/output/qcow2/disk-arm.qcow2}"
: "${QEMU_MEMORY:=3072}"
: "${QEMU_FLEET_MEMORY:=2048}"
: "${QEMU_CPUS:=2}"
: "${QEMU_BOOT_TIMEOUT:=180}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${FLEET_SIZE:=4}"
: "${RUN_CHATBOT_EXTENSION:=1}"
: "${RUN_FLEET_EXTENSION:=1}"

MAIN_VM="demo-m5"

# ── All VMs to manage ─────────────────────────────────────────────────────────
FLEET_NAMES=()
if [[ "${RUN_FLEET_EXTENSION}" == "1" ]]; then
  for i in $(seq 1 "${FLEET_SIZE}"); do
    FLEET_NAMES+=("fleet-$i")
  done
fi

ALL_VMS=("${MAIN_VM}" "${FLEET_NAMES[@]}")

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  local rc=$?
  echo ""
  echo "==> Stopping all QEMU VMs..."
  for vm in "${ALL_VMS[@]}"; do
    "${SCRIPT_DIR}/qemu-vm.sh" stop "${vm}" 2>/dev/null || true
  done
  exit "${rc}"
}
trap cleanup EXIT INT TERM

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ -f "${QEMU_DISK}" ]] || {
  echo "ERROR: QEMU disk not found: ${QEMU_DISK}" >&2
  echo "  Run ./scripts/prepare-demo-m5.sh first." >&2
  exit 1
}
[[ -f "${VM_SSH_KEY}" ]] || { echo "ERROR: SSH key not found: ${VM_SSH_KEY}" >&2; exit 1; }

ssh_ok() {
  ssh -i "${VM_SSH_KEY}" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o BatchMode=yes -o ConnectTimeout=10 \
    "demo@$1" "echo ok" 2>/dev/null
}

# ── Start main VM ─────────────────────────────────────────────────────────────
echo "==> Starting main VM '${MAIN_VM}'"
QEMU_MEMORY="${QEMU_MEMORY}" "${SCRIPT_DIR}/qemu-vm.sh" start "${MAIN_VM}" "${QEMU_DISK}"

# ── Start fleet VMs in parallel ───────────────────────────────────────────────
if [[ "${#FLEET_NAMES[@]}" -gt 0 ]]; then
  echo "==> Starting ${#FLEET_NAMES[@]} fleet VMs in parallel..."
  for vm in "${FLEET_NAMES[@]}"; do
    QEMU_MEMORY="${QEMU_FLEET_MEMORY}" "${SCRIPT_DIR}/qemu-vm.sh" start "${vm}" "${QEMU_DISK}" &
  done
  wait
  echo "==> All fleet VMs started"
fi

# ── Wait for all IPs ──────────────────────────────────────────────────────────
echo "==> Waiting for all VMs to boot and get IPs..."

MAIN_IP="$("${SCRIPT_DIR}/qemu-vm.sh" ip "${MAIN_VM}" "${QEMU_BOOT_TIMEOUT}")"
echo "    ${MAIN_VM}: ${MAIN_IP}"

FLEET_TARGETS=""
if [[ "${#FLEET_NAMES[@]}" -gt 0 ]]; then
  FLEET_IPS=()
  for vm in "${FLEET_NAMES[@]}"; do
    ip="$("${SCRIPT_DIR}/qemu-vm.sh" ip "${vm}" "${QEMU_BOOT_TIMEOUT}")"
    FLEET_IPS+=("${ip}")
    echo "    ${vm}: ${ip}"
    FLEET_TARGETS="${FLEET_TARGETS} demo@${ip}"
  done
  FLEET_TARGETS="${FLEET_TARGETS# }"  # trim leading space
fi

# ── Verify SSH on all VMs ─────────────────────────────────────────────────────
echo ""
echo "==> Verifying SSH on all VMs..."
for ip in "${MAIN_IP}" "${FLEET_IPS[@]+"${FLEET_IPS[@]}"}"; do
  result="$(ssh_ok "${ip}")" || { echo "ERROR: SSH to demo@${ip} failed" >&2; exit 1; }
  echo "    demo@${ip}: SSH OK"
done

echo ""
echo "==> All VMs ready"
echo "    Main  : demo@${MAIN_IP}"
[[ -n "${FLEET_TARGETS}" ]] && echo "    Fleet : ${FLEET_TARGETS}"
echo ""

# ── Run demo ──────────────────────────────────────────────────────────────────
export VM_SSH="demo@${MAIN_IP}"
export VM_SSH_KEY="${VM_SSH_KEY}"
export RUN_SNO_EXTENSION=0
export RUN_CHATBOT_EXTENSION="${RUN_CHATBOT_EXTENSION}"
export RUN_FLEET_EXTENSION="${RUN_FLEET_EXTENSION}"
[[ -n "${FLEET_TARGETS}" ]] && export VM_TARGETS="${FLEET_TARGETS}"

# FLEET_APPLY=1: actually execute bootc switch on each fleet VM (not just plan)
export FLEET_APPLY=1

echo "==> Launching demo-run-m5.sh"
exec "${SCRIPT_DIR}/demo-run-m5.sh"
