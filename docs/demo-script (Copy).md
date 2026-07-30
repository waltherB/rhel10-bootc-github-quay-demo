# RHEL 10 bootc Demo Script

## Demo Objective

Show how RHEL Image Mode and bootc can be used to define, build, distribute, boot, update and roll back a Linux operating system through a container-native workflow.

## Target Audience

- Linux platform teams
- OpenShift platform teams
- Enterprise architects
- Infrastructure operations
- Customers considering standardization of RHEL lifecycle management

## Demo Duration Options

### 15 Minute Version

Focus:

- Repository structure
- Containerfile
- Pre-built image in Quay
- Pre-booted VM
- bootc status
- Update/rollback concept

### 30 Minute Version

Focus:

- Local build
- Push to Quay
- QCOW2 generation or pre-generated QCOW2
- VM boot
- Update story
- Rollback story

### 60 Minute Version

Focus:

- Full pipeline
- Signing
- SBOM
- Quay scanning
- OpenShift Virtualization extension
- Service/productization discussion

## Pre-Flight

Set variables:

```bash
export QUAY_IMAGE="quay.io/<namespace>/<repository>"
export IMAGE_TAG="demo"
export IMAGE="${QUAY_IMAGE}:${IMAGE_TAG}"
export TARGET_PLATFORM="linux/arm64"
```

Validate tools:

```bash
command -v git
command -v podman
podman version
podman info
```

Login:

```bash
podman login registry.redhat.io
podman login quay.io
```

Validate repository:

```bash
git status --short
git log --oneline -5
```

## Step 1 - Explain The Problem

Speaker notes:

Traditional Linux lifecycle management often results in drift, manual patching and inconsistent server states. The point of this demo is to show an alternative where the operating system is built, versioned and distributed like a software artifact.

## Step 2 - Show The Repository

Commands:

```bash
find . -maxdepth 2 -type f | sort
```

Explain:

- `Containerfile` defines the OS image.
- `scripts/` supports local demo operations.
- `.github/workflows/` supports CI/CD.
- `docs/` contains runbooks and demo material.
- `.agent/` contains Copilot agent instructions and workflows.

Expected output:

A clear repository structure with build, script and documentation files.

## Step 3 - Review The Containerfile

Commands:

```bash
sed -n '1,200p' Containerfile
```

Speaker notes:

This is the key shift. Instead of manually configuring a server after installation, we define the intended OS state before deployment.

Look for:

- Base image
- Package installation
- Files copied into image
- systemd units enabled
- Demo marker files

## Step 4 - Build The Image Locally

Preferred script:

```bash
./scripts/local-build.sh
```

If no script exists, use:

```bash
podman build \
  --platform "$TARGET_PLATFORM" \
  -t "$IMAGE" \
  -f Containerfile \
  .
```

Expected output:

```text
Successfully tagged quay.io/<namespace>/<repository>:demo
```

Validate:

```bash
podman image inspect "$IMAGE" --format '{{ .Architecture }} {{ .Os }}'
```

## Step 5 - Test The Image As A Container

Preferred script:

```bash
./scripts/local-test.sh
```

Generic test:

```bash
podman run --rm -it "$IMAGE" /usr/bin/bash -lc 'cat /etc/os-release; cat /etc/demo-release || true'
```

Speaker notes:

This does not replace booting the OS, but it gives fast validation that the image contains the expected content.

## Step 6 - Push To Quay

Preferred script:

```bash
./scripts/local-push.sh
```

Generic command:

```bash
podman push "$IMAGE"
```

Validate:

```bash
podman pull "$IMAGE"
```

Speaker notes:

Quay becomes the distribution point for the operating system image. This is what enables systems to consume OS updates from an image registry.

## Step 7 - Optional Signing

If cosign is configured:

```bash
cosign sign "$IMAGE"
```

If keyless signing is configured, validate the required identity flow before the live demo.

Speaker notes:

This is where the demo moves from convenience to supply-chain control.

## Step 8 - Generate QCOW2

Preferred script:

```bash
./scripts/local-qcow2.sh
```

Generic pattern:

```bash
mkdir -p output
sudo podman run \
  --rm \
  -it \
  --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --local "$IMAGE"
```

Important:

The exact bootc-image-builder image and flags may differ depending on the repository and platform. Validate this before the demo.

Expected output:

```text
output/qcow2/disk.qcow2
```

## Step 9 - Boot VM

Manual UTM flow:

1. Create a new VM.
2. Import QCOW2 disk.
3. Ensure architecture matches host.
4. Boot VM.
5. Log in.

Validate inside VM:

```bash
cat /etc/os-release
sudo bootc status
cat /etc/demo-release || true
```

Speaker notes:

Now the container-defined OS is a running system.

## Step 10 - Demonstrate Update

Change demo marker:

```bash
echo "RHEL bootc demo image version: v2" > files/demo-release
```

Build and push a new tag:

```bash
export IMAGE_TAG="v2"
export IMAGE="${QUAY_IMAGE}:${IMAGE_TAG}"
podman build --platform "$TARGET_PLATFORM" -t "$IMAGE" -f Containerfile .
podman push "$IMAGE"
```

Inside VM, switch or upgrade depending on current configuration:

```bash
sudo bootc switch --apply "$IMAGE"
```

or:

```bash
sudo bootc upgrade --apply
```

Validate after reboot:

```bash
sudo bootc status
cat /etc/demo-release || true
```

## Step 11 - Demonstrate Rollback

Inside VM:

```bash
sudo bootc rollback
sudo systemctl reboot
```

Validate:

```bash
sudo bootc status
cat /etc/demo-release || true
```

Speaker notes:

The business message is that update risk changes. We are no longer hoping that a set of mutable changes worked. We are moving between known image states.

## Step 12 - Close The Demo

Closing message:

This is not just a new way to install Linux. It is a new operating model for Linux lifecycle management. We can now define, review, build, distribute, verify, update and roll back the operating system through controlled pipelines.

## Cleanup

```bash
podman images | grep bootc || true
podman system df
```

Optional cleanup:

```bash
rm -rf output/qcow2
```

Do not delete backup demo images before a presentation.
