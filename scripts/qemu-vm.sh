#!/usr/bin/env bash
# ============================================================
#  qemu-vm.sh — lifecycle manager for bootc demo ARM64 VMs
#
#  Launches RHEL bootc VMs using qemu-system-aarch64 with
#  vmnet-shared networking (192.168.64.0/24, same subnet as UTM).
#  Each VM gets its own overlay disk, UEFI vars copy, and a
#  deterministic MAC so DHCP hands out a stable-ish IP.
#
#  REQUIRES: sudo  (vmnet-shared needs root on macOS)
#
#  Usage:
#    ./scripts/qemu-vm.sh start  [NAME] [DISK_QCOW2]
#    ./scripts/qemu-vm.sh stop   [NAME]
#    ./scripts/qemu-vm.sh ip     [NAME]     # waits until IP is known
#    ./scripts/qemu-vm.sh status [NAME]
#    ./scripts/qemu-vm.sh list
#    ./scripts/qemu-vm.sh stopall
#
#  NAME defaults to "demo".  Multiple VMs can run simultaneously
#  with different names.
#
#  Liveness is determined by the presence of the QMP monitor socket,
#  which QEMU creates on startup and removes on exit.  No wrapper-PID
#  tracking is needed.
#
#  State is kept under:
#    ${QEMU_RUN_DIR}/<name>/   (default: /tmp/qemu-bootc-demo/<name>)
#
#  Environment overrides:
#    QEMU_DISK          path to the base qcow2 (read-only backing file)
#    QEMU_EFI_CODE      path to edk2-aarch64-code.fd
#    QEMU_EFI_VARS_TPL  path to the UEFI vars template (copied per-VM)
#    QEMU_MEMORY        RAM in MB (default 3072)
#    QEMU_CPUS          vCPUs (default 2)
#    QEMU_BOOT_TIMEOUT  seconds to wait for IP (default 180)
#    QEMU_RUN_DIR       runtime state root (default /tmp/qemu-bootc-demo)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

# ── Defaults ──────────────────────────────────────────────────────────────────
: "${QEMU_DISK:=${REPO_DIR}/output/qcow2/disk-arm.qcow2}"
: "${QEMU_EFI_CODE:=/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"
: "${QEMU_EFI_VARS_TPL:=${HOME}/.config/qemu/demo-bootc-arm64-vars.fd}"
: "${QEMU_MEMORY:=3072}"
: "${QEMU_CPUS:=2}"
: "${QEMU_BOOT_TIMEOUT:=180}"
: "${QEMU_RUN_DIR:=/tmp/qemu-bootc-demo}"

QEMU_BIN="$(command -v qemu-system-aarch64 2>/dev/null || true)"
QEMU_IMG_BIN="$(command -v qemu-img 2>/dev/null || true)"

# ── Helpers ───────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

vm_dir()      { echo "${QEMU_RUN_DIR}/$1"; }
serial_log()  { echo "${QEMU_RUN_DIR}/$1/serial.log"; }
monitor_sock(){ echo "${QEMU_RUN_DIR}/$1/monitor.sock"; }
ip_file()     { echo "${QEMU_RUN_DIR}/$1/ip"; }
# The QEMU process name we pass via -name so pgrep can find it
qemu_proc_name() { echo "bootc-$1"; }

# VM is running if its QMP monitor socket exists and QEMU is alive.
is_running() {
  local name="$1"
  local sock
  sock="$(monitor_sock "${name}")"
  [[ -S "${sock}" ]] || return 1
  # Verify the process that owns the socket is still alive via pgrep
  pgrep -f "name $(qemu_proc_name "${name}")" >/dev/null 2>&1
}

# Derive a deterministic MAC from the VM name (locally administered, unicast).
mac_for_name() {
  python3 -c "
import hashlib, sys
h = hashlib.md5(sys.argv[1].encode()).digest()
print('52:54:00:{:02x}:{:02x}:{:02x}'.format(h[0], h[1], h[2]))
" "$1"
}

# Send a QMP command and wait for the response (fire-and-forget style).
qmp_cmd() {
  local sock="$1"
  local cmd="$2"
  python3 - "${sock}" "${cmd}" <<'PY' 2>/dev/null || true
import json, socket, sys
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
    s.settimeout(5)
    s.connect(sys.argv[1])
    f = s.makefile("rwb", buffering=0)
    while "QMP" not in json.loads(f.readline()): pass
    f.write(b'{"execute":"qmp_capabilities"}\r\n')
    f.readline()
    f.write((sys.argv[2] + "\r\n").encode())
    f.readline()
PY
}

# ── start ─────────────────────────────────────────────────────────────────────
cmd_start() {
  local name="${1:-demo}"
  local disk="${2:-${QEMU_DISK}}"

  [[ -x "${QEMU_BIN}" ]]          || die "qemu-system-aarch64 not found"
  [[ -x "${QEMU_IMG_BIN}" ]]      || die "qemu-img not found"
  [[ -f "${disk}" ]]              || die "disk image not found: ${disk}"
  [[ -f "${QEMU_EFI_CODE}" ]]     || die "EFI code not found: ${QEMU_EFI_CODE}"
  [[ -f "${QEMU_EFI_VARS_TPL}" ]] || die "EFI vars template not found: ${QEMU_EFI_VARS_TPL}
  Create it with:
    mkdir -p \$(dirname ${QEMU_EFI_VARS_TPL})
    dd if=/dev/zero bs=1m count=64 | tr '\\0' '\\377' > ${QEMU_EFI_VARS_TPL}"

  if is_running "${name}"; then
    info "VM '${name}' is already running"
    return 0
  fi

  local dir mac
  dir="$(vm_dir "${name}")"
  mac="$(mac_for_name "${name}")"
  mkdir -p "${dir}"
  rm -f "${dir}/ip" "${dir}/monitor.sock"

  info "Creating overlay disk for '${name}'"
  "${QEMU_IMG_BIN}" create -q -f qcow2 -F qcow2 -b "${disk}" "${dir}/disk.qcow2"

  info "Copying UEFI vars for '${name}'"
  cp "${QEMU_EFI_VARS_TPL}" "${dir}/vars.fd"

  info "Starting VM '${name}' (MAC ${mac}, ${QEMU_MEMORY}MB RAM, ${QEMU_CPUS} vCPUs)"
  info "Serial log : $(serial_log "${name}")"
  info "Monitor    : $(monitor_sock "${name}")"

  # Write a launcher script that sudo will execute.  This avoids shell quoting
  # issues with redirection across the sudo boundary, and works on macOS where
  # setsid is not available.
  cat > "${dir}/launch.sh" <<LAUNCHER
#!/bin/bash
exec "${QEMU_BIN}" \\
  -machine virt,accel=hvf \\
  -cpu host \\
  -smp ${QEMU_CPUS} \\
  -m ${QEMU_MEMORY} \\
  -name "$(qemu_proc_name "${name}")" \\
  -drive "if=pflash,format=raw,unit=0,file=${QEMU_EFI_CODE},readonly=on" \\
  -drive "if=pflash,format=raw,unit=1,file=${dir}/vars.fd" \\
  -device virtio-blk-pci,drive=disk0,bootindex=0 \\
  -drive "if=none,media=disk,id=disk0,file=${dir}/disk.qcow2,discard=unmap,detect-zeroes=unmap" \\
  -device "virtio-net-pci,netdev=net0,mac=${mac}" \\
  -netdev vmnet-shared,id=net0 \\
  -device virtio-rng-pci \\
  -display none \\
  -serial "file:${dir}/serial.log" \\
  -monitor "unix:${dir}/monitor.sock,server=on,wait=off" \\
  >>"${dir}/qemu.log" 2>&1
LAUNCHER
  chmod +x "${dir}/launch.sh"

  # sudo bash runs the launcher in the background; stdio is already redirected
  # inside the script so the sudo process itself can exit cleanly.
  sudo bash "${dir}/launch.sh" &

  # Wait for the monitor socket to appear — that means QEMU initialised fully.
  local elapsed=0
  while (( elapsed < 30 )); do
    [[ -S "${dir}/monitor.sock" ]] && break
    sleep 1
    elapsed=$(( elapsed + 1 ))
  done

  [[ -S "${dir}/monitor.sock" ]] || {
    echo "ERROR: QEMU did not create monitor socket within 30s." >&2
    echo "--- qemu.log ---" >&2
    cat "${dir}/qemu.log" >&2
    exit 1
  }

  info "VM '${name}' started (proc name: $(qemu_proc_name "${name}"))"
}

# ── ip ────────────────────────────────────────────────────────────────────────
cmd_ip() {
  local name="${1:-demo}"
  local timeout="${2:-${QEMU_BOOT_TIMEOUT}}"
  local cached
  cached="$(ip_file "${name}")"

  if [[ -f "${cached}" ]]; then
    cat "${cached}"
    return 0
  fi

  is_running "${name}" || die "VM '${name}' is not running"

  info "Waiting for '${name}' to acquire an IP (up to ${timeout}s)..." >&2
  local slog elapsed=0 ip=""
  slog="$(serial_log "${name}")"

  while (( elapsed < timeout )); do
    # RHEL bootc prints:   enp0s2: 192.168.64.x fd13:...
    # just before the login prompt
    ip="$(grep -aEo 'enp[0-9a-z]+: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "${slog}" 2>/dev/null \
          | head -1 | awk '{print $2}' || true)"
    if [[ -n "${ip}" ]]; then
      echo "${ip}" > "${cached}"
      echo "${ip}"
      return 0
    fi
    sleep 3
    elapsed=$(( elapsed + 3 ))
    (( elapsed % 30 == 0 )) && info "  Still waiting... (${elapsed}/${timeout}s)" >&2
    is_running "${name}" || die "VM '${name}' exited before getting an IP"
  done

  echo "ERROR: VM '${name}' did not report an IP within ${timeout}s" >&2
  tail -20 "${slog}" >&2 || true
  return 1
}

# ── stop ─────────────────────────────────────────────────────────────────────
cmd_stop() {
  local name="${1:-demo}"
  local dir sock
  dir="$(vm_dir "${name}")"
  sock="$(monitor_sock "${name}")"

  if ! is_running "${name}"; then
    info "VM '${name}' is not running"
    rm -f "${sock}" "${dir}/ip"
    return 0
  fi

  # Graceful shutdown via QMP
  info "Sending powerdown to '${name}'"
  qmp_cmd "${sock}" '{"execute":"system_powerdown"}'

  local elapsed=0
  while (( elapsed < 8 )); do
    is_running "${name}" || break
    sleep 1
    elapsed=$(( elapsed + 1 ))
  done

  # Force kill if still running
  if is_running "${name}"; then
    info "Force-killing '${name}'"
    sudo pkill -f "name $(qemu_proc_name "${name}")" 2>/dev/null || true
    sleep 2
  fi

  rm -f "${sock}" "${dir}/ip"
  info "VM '${name}' stopped"
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
  local name="${1:-demo}"
  local ip_f pid
  ip_f="$(ip_file "${name}")"
  if is_running "${name}"; then
    pid="$(pgrep -f "name $(qemu_proc_name "${name}")" | head -1)"
    local ip="(booting...)"
    [[ -f "${ip_f}" ]] && ip="$(<"${ip_f}")"
    echo "VM '${name}': RUNNING  ip=${ip}  pid=${pid}"
  else
    echo "VM '${name}': stopped"
  fi
}

# ── list ──────────────────────────────────────────────────────────────────────
cmd_list() {
  if [[ ! -d "${QEMU_RUN_DIR}" ]]; then
    echo "(no VMs)"
    return 0
  fi
  local found=0
  for d in "${QEMU_RUN_DIR}"/*/; do
    [[ -d "${d}" ]] || continue
    cmd_status "$(basename "${d}")"
    found=1
  done
  (( found )) || echo "(no VMs)"
}

# ── stopall ───────────────────────────────────────────────────────────────────
cmd_stopall() {
  if [[ ! -d "${QEMU_RUN_DIR}" ]]; then return 0; fi
  for d in "${QEMU_RUN_DIR}"/*/; do
    [[ -d "${d}" ]] || continue
    cmd_stop "$(basename "${d}")"
  done
}

# ── dispatch ──────────────────────────────────────────────────────────────────
ACTION="${1:-help}"
shift || true

case "${ACTION}" in
  start)   cmd_start   "$@" ;;
  stop)    cmd_stop    "$@" ;;
  ip)      cmd_ip      "$@" ;;
  status)  cmd_status  "$@" ;;
  list)    cmd_list ;;
  stopall) cmd_stopall ;;
  *)
    echo "Usage: $0 {start|stop|ip|status|list|stopall} [name] [disk]"
    exit 1
    ;;
esac
