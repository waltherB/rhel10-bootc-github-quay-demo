#!/usr/bin/env bash
set -euo pipefail
IMAGE="${1:-quay.io/waba/bootc-guide:prod}"

sudo bootc switch --apply "$IMAGE"
