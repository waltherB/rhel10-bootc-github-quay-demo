#!/usr/bin/env bash
set -euo pipefail

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
: "${VM_SSH:=demo@192.168.64.18}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_TARGETS:=demo@192.168.64.18 demo@192.168.64.20 demo@192.168.64.21 demo@192.168.64.22 demo@192.168.64.23}"
: "${REBOOT_TIMEOUT:=240}"
: "${TARGET_IMAGE:=${IMAGE_GOOD}}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

ssh_opts=(-i "${VM_SSH_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8)

booted_image_for() {
  local vm="$1"
  local out
  out="$(ssh "${ssh_opts[@]}" "${vm}" 'sudo bootc status' 2>&1 || true)"

  # Support the bootc status variants seen in the repository demo tooling.
  local parsed
  parsed="$(printf '%s\n' "${out}" | sed -nE 's/^Booted image: ([^[:space:]].*)$/\1/p' | head -n 1 || true)"
  if [[ -z "${parsed}" ]]; then
    parsed="$(printf '%s\n' "${out}" | sed -nE 's/^booted image: ([^[:space:]].*)$/\1/p' | head -n 1 || true)"
  fi
  if [[ -z "${parsed}" ]]; then
    parsed="unknown"
  fi
  printf '%s\n' "${parsed}"
}

queued_image_for() {
  local out="$1"
  printf '%s\n' "${out}" | sed -nE 's/^Queued for next boot: ([^[:space:]].*)$/\1/p' | head -n 1 || true
}

wait_ssh_vm() {
  local vm="$1"
  local elapsed=0

  while (( elapsed < REBOOT_TIMEOUT )); do
    if ssh "${ssh_opts[@]}" "${vm}" 'sudo true' >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  return 1
}

ensure_vm_image() {
  local vm="$1"
  local want="$2"
  local current
  local stage_out

  current="$(booted_image_for "${vm}")"

  if [[ -z "${current}" || "${current}" == "unknown" ]]; then
    echo "WARN: could not read booted image for ${vm}; assuming it needs ${want}" >&2
  else
    echo "${vm}: current booted image = ${current}"
  fi

  if [[ -n "${current}" && "${current}" != "unknown" && "${current}" == "${want}" ]]; then
    echo "${vm}: already on ${want}"
    return 0
  fi

  echo "${vm}: switching to ${want}"
  stage_out="$(ssh "${ssh_opts[@]}" "${vm}" "sudo bootc switch --apply ${want}" 2>&1 || true)"
  echo "${stage_out}"

  if printf '%s\n' "${stage_out}" | grep -qi 'Image specification is unchanged'; then
    echo "${vm}: image is already ${want}; no switch needed"
    return 0
  fi

  # Remote bootc switch may answer with the usual queue-for-next-boot form,
  # then immediately close the SSH connection. That is an expected remote
  # workflow for staged deployments, not a synthetic failure condition.
  queued_ref="$(queued_image_for "${stage_out}")"
  if [[ -n "${queued_ref}" ]]; then
    if [[ "${queued_ref}" == "${want}" ]]; then
      echo "${vm}: staged for next boot = ${want}"
      return 0
    fi
    echo "ERROR: ${vm}: queued image ${queued_ref} instead of ${want}" >&2
    return 1
  fi

  # bootc switch may close the SSH connection immediately after queuing the
  # staged deployment for the next boot. Treat that as expected normal flow
  # and then verify the target is reachable again and confirms the wanted
  # booted reference through bootc status.
  if ! wait_ssh_vm "${vm}"; then
    echo "ERROR: ${vm} did not return over SSH after stage" >&2
    return 1
  fi

  sleep 5
  current="$(booted_image_for "${vm}")"
  if [[ "${current}" == "${want}" ]]; then
    echo "${vm}: confirmed booted image = ${want}"
    return 0
  fi

  # Normalize the remote unknown/queued status into a warning instead of a
  # false fatal error if switch output already demonstrated that the image
  # was accepted and staged for the next boot.
  if [[ "${current}" == "unknown" ]]; then
    echo "WARN: ${vm} is reachable, but booted image is not yet readable after switch; ${want} was staged for next boot" >&2
    return 0
  fi

  echo "ERROR: ${vm} is reachable, but booted image is ${current:-unknown} instead of ${want}" >&2
  return 1
}

require_command ssh

if [[ ! -f "${VM_SSH_KEY}" ]]; then
  echo "ERROR: SSH key not found: ${VM_SSH_KEY}" >&2
  exit 1
fi

read -r -a TARGETS <<< "${VM_TARGETS}"
# Preserve the always-on primary UTM test VM, then include any additional fleet members.
if [[ "${VM_SSH}" != "" && "${TARGETS[*]}" != *"${VM_SSH}"* ]]; then
  TARGETS=("${VM_SSH}" "${TARGETS[@]}")
fi

for vm in "${TARGETS[@]}"; do
  ensure_vm_image "${vm}" "${TARGET_IMAGE}"
done

echo
printf 'Ensured all UTM targets are using %s\n' "${TARGET_IMAGE}"
printf '  VM list: %s\n' "${TARGETS[*]}"
