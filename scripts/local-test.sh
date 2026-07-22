#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"

podman rm -f bootc-test 2>/dev/null || true
podman run --rm -d -p 8080:80 --name bootc-test "$IMAGE"

echo "Waiting for httpd to be ready..."
for i in {1..15}; do
  if curl -fsS http://127.0.0.1:8080 | head; then
    break
  fi
  echo "  attempt ${i}/15 failed, retrying in 2s..."
  sleep 2
  if [[ $i -eq 15 ]]; then
    echo "ERROR: httpd did not respond after 30s"
    podman stop bootc-test
    exit 1
  fi
done

podman exec bootc-test cat /etc/motd
podman stop bootc-test
