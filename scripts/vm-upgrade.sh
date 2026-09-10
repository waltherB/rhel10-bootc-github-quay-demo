#!/usr/bin/env bash
# Run this INSIDE the VM to pull the latest image reference recorded by bootc
# (the UTM VM normally tracks :dev-arm64) and reboot into it.
set -euo pipefail

run_sudo() {
  if [[ -n "${VM_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "${VM_SUDO_PASSWORD}" | sudo -S -- "$@"
  else
    sudo -- "$@"
  fi
}

echo "=== Current booted image ==="
run_sudo bootc status

echo ""
echo "=== Checking for update ==="
run_sudo bootc upgrade --check

echo ""
echo "=== Pulling and staging new image ==="
run_sudo bootc upgrade

echo ""
echo "=== Rebooting into new image in 5 seconds (Ctrl-C to cancel) ==="
sleep 5
run_sudo systemctl reboot
