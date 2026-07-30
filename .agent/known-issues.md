# Known Demo Risks And Recovery Patterns

## Registry Login Failure

### Symptoms

```text
unauthorized
authentication required
requested access to the resource is denied
```

### Verify

```bash
podman login registry.redhat.io
podman login quay.io
podman info --format '{{ json .Registries }}'
```

### Fix

```bash
podman logout registry.redhat.io || true
podman logout quay.io || true
podman login registry.redhat.io
podman login quay.io
```

### Live Demo Recovery

Use a pre-pushed image and explain that registry authentication is normally handled by CI/CD secrets or managed pull secrets.

---

## Quay Namespace Or Image Reference Error

### Symptoms

```text
manifest unknown
repository not found
name unknown
```

### Verify

```bash
echo "$QUAY_IMAGE"
podman image exists "$QUAY_IMAGE:latest" || true
podman pull "$QUAY_IMAGE:latest"
```

### Fix

Confirm the exact image reference:

```text
quay.io/<namespace>/<repository>:<tag>
```

Do not assume that the login username and namespace are identical.

---

## Architecture Mismatch

### Symptoms

- VM does not boot
- Exec format errors
- QEMU/UTM import problems
- Image built as AMD64 but demo host expects ARM64

### Verify

```bash
uname -m
podman image inspect "$IMAGE" --format '{{ .Architecture }}'
```

### Expected On Mac M-Series

```text
Host: arm64/aarch64
Preferred target: linux/arm64
```

### Live Demo Recovery

Use prebuilt image matching the host architecture.

---

## bootc-image-builder Failure

### Symptoms

- QCOW2 output missing
- Permission denied
- Storage mount error
- SELinux label issue
- Image not found from rootful context

### Verify

```bash
podman images
sudo podman images
ls -lah output/ || true
```

### Common Fix

If the image was built rootless but builder runs rootful, copy the image into root storage:

```bash
podman image scp $(whoami)@localhost::$IMAGE root@localhost::$IMAGE
```

If that syntax is not supported in the local Podman version, push to Quay and build from the registry reference instead.

---

## GitHub Actions Runner Architecture

### Symptoms

- Build completes but image is wrong architecture
- ARM64 VM cannot boot image
- QEMU emulation is slow or fails

### Verify

```yaml
runs-on: ubuntu-latest
```

GitHub-hosted Linux runners are commonly x86_64. For ARM64 demo builds, prefer a self-hosted ARM64 runner or local Mac build.

---

## Long Build Time During Demo

### Symptoms

- Audience waits too long
- Network download dominates demo
- Pipeline exceeds session time

### Mitigation

Prepare:

- Pre-built image
- Pre-generated QCOW2
- Pre-booted VM snapshot
- Screenshots of successful build pipeline

---

## VM Not Booting

### Verify

- Architecture matches
- UEFI enabled
- Disk image is valid
- Correct QCOW2 selected
- VM memory >= 4 GB if possible
- VM CPU >= 2 vCPU if possible

### Recovery

Use backup VM snapshot and continue with bootc status/update explanation.

---

## Secrets Printed In Logs

### Prevention

Scripts must mask:

- TOKEN
- PASSWORD
- SECRET
- KEY
- AUTH

Use a masking helper in shell output.

### Recovery

Stop sharing screen, rotate the affected credential and remove log output from recording if relevant.
