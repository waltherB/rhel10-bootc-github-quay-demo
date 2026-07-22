#!/usr/bin/env bash
# Run this INSIDE the VM to pull the latest :prod image and reboot into it.
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
