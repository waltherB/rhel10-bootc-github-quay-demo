#!/usr/bin/env bash
set -euo pipefail

# Apply one tested bootc image to several ARM64 VMs.
# Default mode is plan-only; use FLEET_APPLY=1 to execute the switch.

: "${IMAGE_UPDATE:=quay.io/waba/bootc-guide:demo-v3-fixed-arm64}"
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
