# Live Demo Checklist

## Go / No-Go Rule

If two or more critical dependencies fail, switch to backup demo path.

Critical dependencies:

- Quay access
- Red Hat registry access
- Podman working
- VM bootable
- Correct architecture image available

## 24 Hours Before Demo

### Repository

```bash
git status
git pull --rebase
find . -maxdepth 3 -type f | sort
```

Check:

- README updated
- Demo script updated
- Scripts executable
- No secrets in files

```bash
grep -RniE 'password|token|secret|pullsecret|auth' . \
  --exclude-dir=.git \
  --exclude='*.zip' || true
```

### GitHub Actions

Check:

- Latest workflow run green
- Required secrets configured
- Variables configured

Expected variables:

```text
QUAY_IMAGE
TARGET_PLATFORM
```

Expected secrets:

```text
RH_REGISTRY_USERNAME
RH_REGISTRY_PASSWORD
QUAY_USERNAME
QUAY_TOKEN
```

### Quay

```bash
podman login quay.io
podman pull "$QUAY_IMAGE:latest"
podman image inspect "$QUAY_IMAGE:latest" --format '{{ .Architecture }}'
```

### Red Hat Registry

```bash
podman login registry.redhat.io
podman pull registry.redhat.io/rhel10/rhel-bootc:latest
```

If the exact base image tag differs in the repository, use the repository-defined tag.

### Podman

```bash
podman version
podman info
podman system df
```

Ensure enough disk space:

```bash
df -h .
```

### VM Backup

Prepare:

- Pre-built QCOW2
- Pre-imported UTM VM
- Snapshot before update demo
- Known login credentials or SSH key
- Screenshot folder

Recommended backup folder:

```text
demo-backup/
  screenshots/
  qcow2/
  command-output/
```

## 2 Hours Before Demo

Run:

```bash
./scripts/00-check-prereqs.sh || true
```

If this script does not exist, manually validate:

```bash
command -v podman
command -v git
command -v ssh
podman login quay.io
podman login registry.redhat.io
```

Build or pull image:

```bash
podman pull "$QUAY_IMAGE:latest" || ./scripts/02-build-local.sh
```

Verify architecture:

```bash
uname -m
podman image inspect "$QUAY_IMAGE:latest" --format '{{ .Architecture }}'
```

Boot backup VM and verify:

```bash
sudo bootc status
cat /etc/demo-release || true
```

## 15 Minutes Before Demo

- Disable notifications
- Open terminal tabs
- Increase terminal font size
- Pre-open GitHub repo
- Pre-open Quay repository
- Pre-open VM console
- Validate network
- Have backup commands ready

## Demo Terminal Layout

Recommended tabs:

```text
1_repo
2_build
3_registry
4_vm_ssh
5_recovery
```

## Go / No-Go Decision

### Green

- Quay reachable
- Image available
- VM boots
- Podman working
- Backup ready

Proceed with full demo.

### Yellow

- One dependency unstable
- Backup VM works

Proceed with shortened demo.

### Red

- Registry unavailable
- VM broken
- No backup image

Use slide/screenshot-based fallback.

## Backup Demo Path

If live build fails:

1. Explain intended build flow.
2. Show GitHub Actions previous successful run.
3. Pull pre-built image.
4. Continue with VM and bootc status.

If Quay fails:

1. Use local image if available.
2. Use pre-generated QCOW2.
3. Explain registry role conceptually.

If VM fails:

1. Show screenshots.
2. Show captured command output.
3. Continue with architecture explanation.
