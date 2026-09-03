#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"
 
# Requires: brew install cosign
# cosign uses its own credential store — log in separately from podman:
#   cosign login quay.io -u <username> -p <token>
 
# Who is expected to sign, and via which OIDC provider.
# Override at invocation time, e.g.:
#   CERT_IDENTITY=you@example.com CERT_OIDC_ISSUER=https://accounts.google.com ./local-sign-keyless.sh
# Defaults below match signing in with a GitHub account at the sigstore OAuth screen,
# which issues tokens from GitHub itself (not GitHub Actions, and not Google).
CERT_IDENTITY="${CERT_IDENTITY:-walther.barnett@gmail.com}"
CERT_OIDC_ISSUER="${CERT_OIDC_ISSUER:-https://github.com/login/oauth}"
 
# Resolve the tag to a digest so cosign signs the exact image that was pushed
echo "Resolving digest for ${IMAGE}..."
DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}")"
IMAGE_BY_DIGEST="${IMAGE%:*}@${DIGEST}"
echo "Signing ${IMAGE_BY_DIGEST}"
 
COSIGN_YES=true cosign sign "${IMAGE_BY_DIGEST}"
 
echo "Verifying signature for identity ${CERT_IDENTITY} (issuer ${CERT_OIDC_ISSUER})..."
cosign verify "${IMAGE_BY_DIGEST}" \
  --certificate-identity="${CERT_IDENTITY}" \
  --certificate-oidc-issuer="${CERT_OIDC_ISSUER}"
 
echo "Signature verified for ${IMAGE} (${DIGEST}) as ${CERT_IDENTITY} via ${CERT_OIDC_ISSUER}"
 
