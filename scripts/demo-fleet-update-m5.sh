#!/usr/bin/env bash
set -euo pipefail

# Apply one tested bootc image to several ARM64 VMs.
# Default mode is plan-only; use FLEET_APPLY=1 to execute the switch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_UPDATE_OVERRIDE="${IMAGE_UPDATE-}"
IMAGE_UPDATE_WAS_SET="${IMAGE_UPDATE+x}"
VM_TARGETS_OVERRIDE="${VM_TARGETS-}"
VM_TARGETS_WAS_SET="${VM_TARGETS+x}"
FLEET_APPLY_OVERRIDE="${FLEET_APPLY-}"
FLEET_APPLY_WAS_SET="${FLEET_APPLY+x}"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

if [[ -n "${IMAGE_UPDATE_WAS_SET}" ]]; then
  IMAGE_UPDATE="${IMAGE_UPDATE_OVERRIDE}"
else
  IMAGE_UPDATE="${IMAGE_FIXED:-${QUAY_REPO:-quay.io/waba/bootc-guide}:demo-v3-fixed-arm64}"
fi
if [[ -n "${VM_TARGETS_WAS_SET}" ]]; then VM_TARGETS="${VM_TARGETS_OVERRIDE}"; fi
if [[ -n "${FLEET_APPLY_WAS_SET}" ]]; then FLEET_APPLY="${FLEET_APPLY_OVERRIDE}"; fi

: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_TARGETS:=${VM_SSH:-demo@192.168.64.18}}"
: "${FLEET_APPLY:=0}"

if [[ "${FLEET_APPLY}" == "1" ]]; then
  echo "Applying ${IMAGE_UPDATE} to the configured VM fleet"
else
  echo "Plan for applying ${IMAGE_UPDATE} to the configured VM fleet"
fi

target_count=0
for target in ${VM_TARGETS}; do
  ((target_count += 1))
  if [[ "${FLEET_APPLY}" == "1" ]]; then
    echo "==> ${target}"
    ssh -i "${VM_SSH_KEY}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      "${target}" sudo bootc switch "${IMAGE_UPDATE}"
  else
    printf '  %s: sudo bootc switch %s\n' "${target}" "${IMAGE_UPDATE}"
  fi
done

if (( target_count == 0 )); then
  echo "ERROR: VM_TARGETS is empty." >&2
  exit 1
fi

if [[ "${FLEET_APPLY}" == "1" ]]; then
  echo
  echo "Image staged on ${target_count} VM(s). Reboot them according to your change window."
else
  echo
  echo "No changes made. Set FLEET_APPLY=1 to execute the plan."
fi
