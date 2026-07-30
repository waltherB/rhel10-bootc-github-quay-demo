# Troubleshooting Guide

## General Debug Pattern

Use this order:

1. Confirm command and exact error.
2. Confirm host architecture.
3. Confirm image reference.
4. Confirm registry login.
5. Confirm local image exists.
6. Confirm rootless vs rootful Podman context.
7. Confirm network/DNS.
8. Confirm disk space.

## Useful Baseline Commands

```bash
uname -a
uname -m
podman version
podman info
podman system df
df -h .
git status --short
git rev-parse --short HEAD
```

## Build Failure

### Symptoms

```text
error building at STEP
no such package
unauthorized
manifest unknown
```

### Check

```bash
podman login registry.redhat.io
podman pull registry.redhat.io/rhel10/rhel-bootc:latest
podman build --no-cache -t test-bootc -f Containerfile .
```

### Likely Causes

- Red Hat registry authentication missing
- Base image tag incorrect
- Package unavailable
- Network issue
- Containerfile syntax issue
- Architecture mismatch

### Fix

Validate base image and build one step at a time. If live, switch to pre-built image.

## Push Failure

### Symptoms

```text
unauthorized
requested access to the resource is denied
repository not found
```

### Check

```bash
podman login quay.io
echo "$QUAY_IMAGE"
podman push "$IMAGE"
```

### Likely Causes

- Wrong Quay namespace
- Token lacks write permission
- Repository does not exist
- Organization policy blocks push

### Fix

Create repo in Quay or correct image reference.

## Pull Failure From VM

### Symptoms

```text
unauthorized
manifest unknown
connection refused
```

### Check Inside VM

```bash
sudo bootc status
sudo podman pull "$IMAGE" || true
cat /etc/containers/registries.conf || true
ls -l /etc/ostree/ || true
```

### Likely Causes

- Private registry credentials not available to host
- Wrong image reference
- DNS/network issue
- TLS/proxy issue

### Fix

For demo, use public test image or preconfigured pull secret. Do not bake personal credentials directly into the image.

## QCOW2 Generation Failure

### Symptoms

```text
permission denied
image not known
output/qcow2 missing
```

### Check

```bash
podman images
sudo podman images
ls -lah output || true
```

### Likely Causes

- Image built rootless but builder runs rootful
- Missing privileged flag
- Incorrect volume mount
- Image reference not available locally
- Architecture mismatch

### Fix Options

Option 1: Push image to Quay and build from registry reference.

Option 2: Copy image to rootful storage if supported:

```bash
podman image scp $(whoami)@localhost::$IMAGE root@localhost::$IMAGE
```

Option 3: Use pre-generated QCOW2 for live demo.

## VM Boot Failure

### Check

- Correct architecture
- UEFI enabled
- QCOW2 valid
- Enough memory
- Correct disk attached
- No corrupted download/copy

Commands on host:

```bash
file output/qcow2/disk.qcow2 || true
ls -lh output/qcow2/disk.qcow2 || true
```

## bootc Update Failure

### Symptoms

```text
upgrade failed
switch failed
cannot fetch image
```

### Check

```bash
sudo bootc status
sudo journalctl -u bootc-fetch-apply-updates --no-pager || true
sudo podman pull "$IMAGE" || true
```

### Likely Causes

- Registry authentication unavailable
- Image architecture mismatch
- Incorrect image tag
- DNS/network
- Image not bootc-compatible

### Fix

Use known-good image tag. If live, explain update flow using captured output and continue to rollback concept.

## Rollback Failure

### Check

```bash
sudo bootc status
rpm-ostree status || true
sudo journalctl -b --no-pager | tail -100
```

### Recovery

If rollback cannot be demonstrated live, use VM snapshot rollback and explain the bootc rollback mechanism.

## Live Demo Rule

If a fix takes more than two minutes, stop troubleshooting live.

Say:

```text
This is exactly why we prepare recovery paths for infrastructure demos. The important concept is that the OS state is an artifact and we can move between known versions.
```

Then continue with backup image, screenshot or pre-booted VM.
