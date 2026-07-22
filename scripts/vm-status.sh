#!/usr/bin/env bash
# Run this INSIDE the VM to verify which image is booted.
# Useful before and after an upgrade to show the audience what changed.
set -euo pipefail

run_sudo() {
  if [[ -n "${VM_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "${VM_SUDO_PASSWORD}" | sudo -S -- "$@"
  else
    sudo -- "$@"
  fi
}

echo "=== bootc status ==="
run_sudo bootc status

echo ""
echo "=== /etc/motd ==="
cat /etc/motd

echo ""
echo "=== httpd check ==="
if curl -fsS http://localhost | head -5; then
  echo "httpd: OK"
else
  echo "httpd: not responding"
fi

echo ""
echo "=== OS release ==="
cat /etc/redhat-release
