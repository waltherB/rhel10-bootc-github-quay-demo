#!/bin/bash
set -euo pipefail

VM_NAME="demo-bootc-arm64"
DISK="/Users/waba/github/rhel10-bootc-github-quay-demo/output/qcow2/disk-arm.qcow2"
FW_CODE="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
FW_VARS="$HOME/.config/qemu/demo-bootc-arm64-vars.fd"
UUID=$(uuidgen | tr 'A-Z' 'a-z')
# One-time setup: create a writable EFI vars store for this VM
mkdir -p "$(dirname "$FW_VARS")"
[ -f "$FW_VARS" ] || cp "$FW_CODE" "$FW_VARS"

qemu-system-aarch64 \
  -machine virt -accel hvf -cpu host \
  -smp 2 -m 2048 \
  -name "$VM_NAME" -uuid "$UUID" \
  -drive if=pflash,format=raw,unit=0,file="$FW_CODE",readonly=on \
  -drive if=pflash,format=raw,unit=1,file="$FW_VARS" \
  -device virtio-blk-pci,drive=disk0,serial=diskarmqcow2,bootindex=0 \
  -drive "if=none,media=disk,id=disk0,file.filename=$DISK,discard=unmap,detect-zeroes=unmap" \
  -device virtio-net-pci,netdev=net0 -netdev vmnet-shared,id=net0 \
  -device virtio-rng-pci \
  -nographic
