#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-chatbot-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${DISK_IMAGE_PATH:=${REPO_DIR}/output/qcow2/disk-arm.qcow2}"
: "${VM_USER:=demo}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${QEMU_MEMORY:=4096}"
: "${QEMU_BOOT_TIMEOUT:=300}"
: "${QEMU_SWITCH_TIMEOUT:=600}"
: "${QEMU_BOOT_KEY_DELAY:=8}"
: "${QEMU_KEEP_TEMP:=0}"

QEMU_BIN="${QEMU_BIN:-$(command -v qemu-system-aarch64 || true)}"
QEMU_IMG="${QEMU_IMG:-$(command -v qemu-img || true)}"
QEMU_EFI_CODE="${QEMU_EFI_CODE:-/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"
QEMU_EFI_VARS_TEMPLATE="${QEMU_EFI_VARS_TEMPLATE:-${HOME}/.config/qemu/demo-bootc-arm64-vars.fd}"
QEMU_SSH_PORT="${QEMU_SSH_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"

require_file() {
  [[ -f "$1" ]] || { echo "ERROR: required file not found: $1" >&2; exit 1; }
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: required command not found: $1" >&2; exit 1; }
}

require_command ssh
require_command python3
[[ -x "${QEMU_BIN}" ]] || { echo "ERROR: qemu-system-aarch64 not found." >&2; exit 1; }
[[ -x "${QEMU_IMG}" ]] || { echo "ERROR: qemu-img not found." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "ERROR: this test expects a native ARM64 Mac." >&2; exit 1; }
require_file "${DISK_IMAGE_PATH}"
require_file "${VM_SSH_KEY}"
require_file "${QEMU_EFI_CODE}"
require_file "${QEMU_EFI_VARS_TEMPLATE}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bootc-qemu.XXXXXX")"
QEMU_PID=""
cleanup() {
  if [[ -n "${QEMU_PID}" ]] && kill -0 "${QEMU_PID}" 2>/dev/null; then
    kill "${QEMU_PID}" 2>/dev/null || true
    wait "${QEMU_PID}" 2>/dev/null || true
  fi
  if [[ "${QEMU_KEEP_TEMP}" == "1" ]]; then
    echo "QEMU files retained at ${TMP_DIR}"
  else
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SSH_TARGET="${VM_USER}@127.0.0.1"
SSH_OPTIONS=(-i "${VM_SSH_KEY}" -p "${QEMU_SSH_PORT}" -o BatchMode=yes
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

remote() {
  ssh "${SSH_OPTIONS[@]}" "${SSH_TARGET}" "$@"
}

press_grub_enter() {
  python3 - "${TMP_DIR}/monitor.sock" <<'PY'
import json
import socket
import sys

def read_response(stream):
    while True:
        message = json.loads(stream.readline())
        if "return" in message:
            return message["return"]
        if "error" in message:
            raise RuntimeError(message["error"].get("desc", str(message["error"])))

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as monitor:
    monitor.settimeout(5)
    monitor.connect(sys.argv[1])
    stream = monitor.makefile("rwb", buffering=0)
    while "QMP" not in json.loads(stream.readline()):
        pass
    stream.write(b'{"execute":"qmp_capabilities"}\r\n')
    read_response(stream)
    command = {
        "execute": "human-monitor-command",
        "arguments": {"command-line": "sendkey ret"},
    }
    stream.write((json.dumps(command) + "\r\n").encode())
    read_response(stream)
PY
}

booted_image() {
  remote sudo bootc status --format json | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["status"]["booted"]["image"]["image"]["image"])'
}

wait_for_ssh() {
  local timeout="$1"
  local elapsed=0
  while (( elapsed < timeout )); do
    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
      echo "ERROR: QEMU exited before the guest became ready." >&2
      cat "${TMP_DIR}/qemu.log" >&2
      return 1
    fi
    if remote sudo true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "ERROR: guest SSH did not become ready within ${timeout}s." >&2
  tail -n 40 "${TMP_DIR}/serial.log" >&2 || true
  return 1
}

wait_for_image() {
  local expected="$1"
  local timeout="$2"
  local elapsed=0
  local actual=""
  while (( elapsed < timeout )); do
    actual="$(booted_image 2>/dev/null || true)"
    if [[ "${actual}" == "${expected}" ]]; then
      printf 'Booted image confirmed: %s\n' "${actual}"
      return 0
    fi
    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
      echo "ERROR: QEMU exited while waiting for ${expected}." >&2
      cat "${TMP_DIR}/qemu.log" >&2
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "ERROR: expected ${expected}, got ${actual:-no SSH response} after ${timeout}s." >&2
  tail -n 40 "${TMP_DIR}/serial.log" >&2 || true
  return 1
}

check_http() {
  local expected="$1"
  if [[ "${expected}" == "up" ]]; then
    remote curl -fsS http://127.0.0.1/ >/dev/null
    echo "HTTP service confirmed active."
  elif remote curl -fsS http://127.0.0.1/ >/dev/null 2>&1; then
    echo "ERROR: broken image unexpectedly serves HTTP." >&2
    return 1
  else
    echo "Expected failure confirmed: broken image does not serve HTTP."
  fi
}

check_guest_network_and_selinux() {
  local quay_status
  echo "SELinux mode: $(remote getenforce)"
  echo "NetworkManager: $(remote systemctl is-active NetworkManager || true)"
  echo "SSH daemon: $(remote systemctl is-active sshd || true)"
  remote ip -brief address
  remote ip route
  remote 'sudo journalctl -b -g "avc: denied" --no-pager -n 20' || true
  if ! quay_status="$(remote curl -sS -o /dev/null -w '%{http_code}' https://quay.io/v2/)"; then
    echo "ERROR: guest cannot reach quay.io after boot." >&2
    return 1
  fi
  if [[ "${quay_status}" != "200" && "${quay_status}" != "401" ]]; then
    echo "ERROR: unexpected quay.io response after boot: HTTP ${quay_status}." >&2
    return 1
  fi
  echo "Guest network confirmed (quay.io returned HTTP ${quay_status})."
}

echo "Creating a temporary qcow2 overlay from ${DISK_IMAGE_PATH}"
"${QEMU_IMG}" create -q -f qcow2 -F qcow2 -b "${DISK_IMAGE_PATH}" "${TMP_DIR}/disk.qcow2"
cp "${QEMU_EFI_VARS_TEMPLATE}" "${TMP_DIR}/vars.fd"

"${QEMU_BIN}" \
  -machine virt,accel=hvf -cpu host -smp 2 -m "${QEMU_MEMORY}" \
  -name bootc-image-validation \
  -drive "if=pflash,format=raw,unit=0,file=${QEMU_EFI_CODE},readonly=on" \
  -drive "if=pflash,format=raw,unit=1,file=${TMP_DIR}/vars.fd" \
  -device virtio-blk-pci,drive=disk0,serial=bootcvalidation,bootindex=0 \
  -drive "if=none,media=disk,id=disk0,file=${TMP_DIR}/disk.qcow2,discard=unmap,detect-zeroes=unmap" \
  -device virtio-net-pci,netdev=net0 \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${QEMU_SSH_PORT}-:22" \
  -device virtio-rng-pci -display none \
  -serial "file:${TMP_DIR}/serial.log" \
  -monitor none -qmp "unix:${TMP_DIR}/monitor.sock,server=on,wait=off" \
  >"${TMP_DIR}/qemu.log" 2>&1 &
QEMU_PID=$!

echo "Waiting for baseline VM on SSH port ${QEMU_SSH_PORT}"
wait_for_ssh "${QEMU_BOOT_TIMEOUT}"
wait_for_image "${IMAGE_GOOD}" "${QEMU_BOOT_TIMEOUT}"
check_guest_network_and_selinux
check_http up

for image in "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}"; do
  echo
  echo "Switching guest to ${image}"
  remote sudo bootc switch "${image}"
  remote sudo systemctl reboot --no-block || true
  echo "Waiting ${QEMU_BOOT_KEY_DELAY}s for the guest boot menu"
  sleep "${QEMU_BOOT_KEY_DELAY}"
  echo "Sending Enter to the QEMU guest via QMP"
  press_grub_enter
  echo "Waiting for ${image} to report as booted"
  wait_for_image "${image}" "${QEMU_SWITCH_TIMEOUT}"
  check_guest_network_and_selinux
  if [[ "${image}" == "${IMAGE_BROKEN}" ]]; then
    check_http down
  else
    check_http up
  fi
done

echo
echo "All bootc images booted and passed the QEMU switch checks."