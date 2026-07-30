# Repository Overview

## Purpose

This repository demonstrates how to build, publish and test a Red Hat Enterprise Linux bootc image as part of an image-based operating system lifecycle.

The repository should support both:

1. Local demo execution from a laptop.
2. Automated build and publish through GitHub Actions.

## Target Demo Environment

Recommended demo environment:

- MacBook Pro with Apple Silicon for local ARM64 demo
- Podman / Podman Desktop
- UTM for local VM testing
- GitHub as source control and CI/CD trigger
- Quay.io as image registry
- Red Hat registry access for base image pull
- Optional cosign for signing
- Optional SBOM tooling

## Conceptual Architecture

```text
Developer
  |
  | git commit / git push
  v
GitHub Repository
  |
  | GitHub Actions or local build script
  v
Container Build
  |
  | podman/buildah build
  v
RHEL bootc Container Image
  |
  | push
  v
Quay.io Registry
  |
  | bootc-image-builder or bootc upgrade
  v
QCOW2 / VM / Target Host
```

## Lifecycle Model

### Build

The desired operating system state is defined in the repository, typically through the Containerfile and supporting files.

### Publish

The generated image is pushed to Quay with a clear tag strategy.

Recommended tags:

```text
latest
main
commit-<short-sha>
vYYYY.MM.DD
stable
candidate
```

### Deploy

For demos, the image can be converted into a QCOW2 image for local VM testing.

### Update

A running bootc system can move to a newer image version through the bootc lifecycle.

### Rollback

Rollback is part of the operational value story. The demo should include either a live rollback or a prepared explanation with captured output.

## Recommended Demo Markers

To make the demo visible, include a simple version marker in the image:

```text
/etc/demo-release
/usr/share/demo/version.txt
```

Example content:

```text
RHEL bootc demo image version: v1
Built from commit: <sha>
```

This makes it easy to show before/after state during update demonstrations.

## Recommended Repository Improvement Roadmap

### Phase 1 - Demo Reliability

- Add pre-flight script
- Add environment variable validation
- Add backup image instructions
- Add live demo checklist

### Phase 2 - Security Story

- Add cosign signing
- Add SBOM generation
- Add Quay vulnerability scan notes
- Add signed image verification narrative

### Phase 3 - Enterprise Story

- Add promotion model: dev -> candidate -> stable
- Add rollback runbook
- Add OpenShift Virtualization import path
- Add Ansible Automation Platform orchestration concept

### Phase 4 - Service Packaging

- Add workshop agenda
- Add customer discovery questions
- Add assessment checklist
- Add delivery approach
