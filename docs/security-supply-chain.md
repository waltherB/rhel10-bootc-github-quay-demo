# Security And Supply Chain Enhancements

## Purpose

This document describes optional enhancements that make the bootc demo more enterprise-relevant.

## Baseline Security Rules

- Do not store secrets in Git.
- Do not add pull secrets directly into committed files.
- Do not print tokens in logs.
- Use GitHub Actions secrets for CI credentials.
- Use Quay robot accounts where appropriate.
- Use short-lived credentials where possible.

## Recommended GitHub Secrets

```text
RH_REGISTRY_USERNAME
RH_REGISTRY_PASSWORD
QUAY_USERNAME
QUAY_TOKEN
```

## Recommended GitHub Variables

```text
QUAY_IMAGE
TARGET_PLATFORM
```

## Image Signing

Recommended tool:

```text
cosign
```

Example command:

```bash
cosign sign "$IMAGE"
```

For a live demo, validate the identity and authentication flow before going on stage.

## SBOM Generation

Recommended tools may include:

```text
syft
cosign attest
```

Example:

```bash
syft "$IMAGE" -o spdx-json > sbom.spdx.json
```

## Vulnerability Scanning

Use Quay vulnerability scanning where available and show the scan result as part of the enterprise story.

## Tagging Strategy

Recommended:

```text
commit-<short-sha>
candidate
stable
latest
```

Avoid using only `latest` for operational rollback stories.

## Promotion Model

```text
Development image
  -> candidate image
  -> stable image
```

Promotion can be implemented by retagging a digest rather than rebuilding.

## Demo Talk Track

```text
Once the OS becomes an image artifact, we can apply the same controls that we already expect in modern application delivery: signing, SBOM, scanning, promotion and traceability.
```

## Future Enterprise Enhancements

- Sigstore/cosign signing
- SBOM published as build artifact
- Vulnerability gate in CI
- Policy approval before stable tag
- Quay robot accounts
- Separate dev and prod repositories
- Digest-pinned deployment references
