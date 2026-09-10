#!/usr/bin/env bash
set -euo pipefail
IMAGE="${IMAGE:-quay.io/waba/bootc-guide:dev}"

# Requires: brew install cosign
# cosign uses its own credential store — log in separately from podman:
#   cosign login quay.io -u <username> -p <token>

# Local signing mode can be selected by exporting:
#   COSIGN_KEY=/path/to/cosign.key
#   COSIGN_PUB=/path/to/cosign.pub
#   COSIGN_CERT=/path/to/cert.pem
#   COSIGN_CERT_CHAIN=/path/to/cert-chain.pem
#   COSIGN_PASSWORD=<passphrase if protected>
#
# This allows the demo to avoid keyless OIDC and SAN/OIDC issuer mismatch
# issues across local environments and CI/CD pipelines.

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

LOCAL_CERT_MODE=0
if [[ -n "${COSIGN_CERT:-}" && -f "${COSIGN_CERT}" ]]; then
  LOCAL_CERT_MODE=1
fi

if [[ -n "${COSIGN_KEY:-}" || "${LOCAL_CERT_MODE}" == "1" ]]; then
  if [[ -n "${COSIGN_KEY:-}" && "${LOCAL_CERT_MODE}" == "1" ]]; then
    echo "local key/public-key and X.509 certificate mode selected"
  elif [[ -n "${COSIGN_KEY:-}" ]]; then
    echo "local key/public-key mode selected"
  elif [[ "${LOCAL_CERT_MODE}" == "1" ]]; then
    echo "local X.509 certificate mode selected"
  fi

  SIGN_ARGS=(sign)
  if [[ -n "${COSIGN_KEY:-}" ]]; then
    SIGN_ARGS+=(--key "${COSIGN_KEY}")
  fi
  if [[ "${LOCAL_CERT_MODE}" == "1" && -n "${COSIGN_CERT:-}" ]]; then
    SIGN_ARGS+=(--cert "${COSIGN_CERT}")
  fi
  if [[ -n "${COSIGN_CERT_CHAIN:-}" && -f "${COSIGN_CERT_CHAIN}" ]]; then
    SIGN_ARGS+=(--cert-chain "${COSIGN_CERT_CHAIN}")
  fi
  SIGN_ARGS+=("${IMAGE_BY_DIGEST}")

  COSIGN_YES=true cosign "${SIGN_ARGS[@]}"

  if [[ -n "${COSIGN_PUB:-}" ]]; then
    echo "Verifying using local public key ${COSIGN_PUB}..."
    cosign verify --key "${COSIGN_PUB}" "${IMAGE_BY_DIGEST}"
  elif [[ "${LOCAL_CERT_MODE}" == "1" && -n "${COSIGN_CERT:-}" ]]; then
    echo "Verifying using local certificate ${COSIGN_CERT}..."
    cosign verify --cert "${COSIGN_CERT}" "${IMAGE_BY_DIGEST}"
  fi
else
  COSIGN_YES=true cosign sign "${IMAGE_BY_DIGEST}"

  echo "Verifying signature for identity ${CERT_IDENTITY} (issuer ${CERT_OIDC_ISSUER})..."
  cosign verify "${IMAGE_BY_DIGEST}" \
    --certificate-identity="${CERT_IDENTITY}" \
    --certificate-oidc-issuer="${CERT_OIDC_ISSUER}"

  echo "Signature verified for ${IMAGE} (${DIGEST}) as ${CERT_IDENTITY} via ${CERT_OIDC_ISSUER}"
fi

