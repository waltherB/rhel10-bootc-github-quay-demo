#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"

# Requires: brew install cosign
# cosign uses its own credential store — log in separately from podman:
#   cosign login quay.io -u <username> -p <token>

# Resolve the tag to a digest so cosign signs the exact image that was pushed
echo "Resolving digest for ${IMAGE}..."
DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}")"
IMAGE_BY_DIGEST="${IMAGE%:*}@${DIGEST}"
echo "Signing ${IMAGE_BY_DIGEST}"

COSIGN_YES=true cosign sign "${IMAGE_BY_DIGEST}"

echo "Verifying signature..."
cosign verify "${IMAGE_BY_DIGEST}" \
  --certificate-identity-regexp '.*' \
  --certificate-oidc-issuer-regexp '.*'

echo "Signature verified for ${IMAGE} (${DIGEST})"
