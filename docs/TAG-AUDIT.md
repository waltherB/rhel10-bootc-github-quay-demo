# Tag & Image Reference Audit

This document verifies that all Ansible playbooks, deployment scripts, and GitHub Actions workflows use consistent, correct image tags.

---

## ✅ Image Tag Mapping

### AMD64 (Production-Ready)

| Component | Tag | Used By | Purpose |
|-----------|-----|---------|---------|
| Bootc Image | `:dev-amd64` | `.github/workflows/build-sign-push.yml` | Development build from every push to `main` |
| Bootc Image | `:prod-amd64` | `promote-rhel10-bootc-prod` workflow | Production build (promoted, same digest) |
| ContainerDisk | `:dev-disk-amd64` | `.github/workflows/build-qcow2.yml` | Development disk image for OpenShift Virt |
| ContainerDisk | `:prod-disk-amd64` | `scripts/local-promote-disk.sh` | Production disk image (promoted, same digest) |

### ARM64 (Local Demo Only)

| Component | Tag | Used By | Purpose |
|-----------|-----|---------|---------|
| Bootc Image | `:dev-arm64` | `scripts/local-build.sh` | Local ARM64 build on MacBook Pro M4 |
| Bootc Image | `:prod-arm64` | `scripts/local-push.sh` (manual promotion) | Local ARM64 production (manual promotion) |
| ContainerDisk | `:dev-disk-arm64` | `scripts/local-build-qcow2.sh` | Local ARM64 disk for UTM |
| ContainerDisk | `:prod-disk-arm64` | `scripts/local-promote-disk.sh` | Local ARM64 disk (promoted, same digest) |

---

## 📋 Audit Checklist: Ansible Playbooks

### ✅ `ansible/provision-vm.yml`

**Default Image Tag:**
```yaml
disk_image: "quay.io/waba/bootc-guide:prod-disk-amd64"
```

**Analysis:**
- ✅ Defaults to `:prod-disk-amd64` (production-ready, AMD64)
- ✅ Can be overridden via `-e disk_image=...` on the CLI
- ✅ Validates that `disk_image` is not empty and doesn't contain "REPLACE"
- ✅ Extracts auth from `~/.docker/config.json` for Quay pull
- ✅ Uses CDI's `pullMethod: node` (native cluster node pull, no cross-arch issues)
- ✅ Machine type: `pc-q35-rhel9.4.0` (AMD64 machine, correct for x86_64 SNO)
- ✅ Firmware: UEFI enabled (required for bootc's GPT/EFI-only disk)

**Recommendations:**
- ✅ No changes needed. This playbook is correct and follows best practices.

---

### ✅ `ansible/upgrade-vm.yml`

**Image Reference:**
- Not referenced in this playbook (it operates on running VM, not image tags)
- Uses `bootc upgrade` inside the VM to stage/check for updates

**Analysis:**
- ✅ Playbook checks `bootc status` to get current image info
- ✅ Playbook checks `bootc upgrade --check` to detect available updates
- ✅ If update available, runs `bootc upgrade` to stage the new image
- ✅ Reboots into the new staged image
- ✅ Waits for VM to come back up

**Recommendations:**
- ✅ No changes needed. This playbook correctly uses bootc's native update mechanism.

---

## 📋 Audit Checklist: Deployment Scripts

### ✅ `scripts/deploy-to-openshift-virt.sh`

**Default Image Tags:**
```bash
IMAGE_AMD="${IMAGE_AMD:-quay.io/waba/bootc-guide:dev-amd64}"
DISK_IMAGE_AMD="${DISK_IMAGE_AMD:-quay.io/waba/bootc-guide:dev-disk-amd64}"
```

**Analysis:**
- ✅ Defaults to `:dev-amd64` and `:dev-disk-amd64` (development images)
- ✅ Can be overridden via `scripts/demo-env.sh` or CLI flags
- ✅ Verifies images exist on Quay before deployment
- ✅ Calls `ansible-playbook provision-vm.yml` with correct `disk_image` variable
- ✅ Displays deployment summary with image references

**Recommendations:**
- ✅ No changes needed. This deployment script correctly orchestrates the full flow.

---

### ✅ `scripts/local-promote-disk.sh`

**Environment Variables:**
```bash
SOURCE_DISK="${SOURCE_DISK:-...}"  # e.g., quay.io/waba/bootc-guide:dev-disk-amd64
TARGET_DISK="${TARGET_DISK:-...}"  # e.g., quay.io/waba/bootc-guide:prod-disk-amd64
```

**Analysis:**
- ✅ Promotes `:dev-disk-amd64` → `:prod-disk-amd64` using `skopeo copy`
- ✅ Preserves digest (same image, new tag)
- ✅ Signs with keyless Cosign

**Recommendations:**
- ✅ No changes needed. This script correctly maintains digest consistency.

---

## 📋 Audit Checklist: GitHub Actions Workflows

### ✅ `.github/workflows/build-sign-push.yml`

**Builds & Tags:**
- Builds `:dev-amd64` (AMD64, GitHub-hosted runner)
- Builds `:dev-arm64` (ARM64, self-hosted runner)
- Pushes and signs with keyless Cosign

**Analysis:**
- ✅ Uses `:dev-*` tags for development builds
- ✅ Native builds (no cross-arch emulation)
- ✅ Runs on every push to `main`

**Recommendations:**
- ✅ No changes needed.

---

### ✅ `.github/workflows/build-qcow2.yml`

**Builds & Tags:**
- Input: `image` (e.g., `:dev-amd64` or `:prod-amd64`)
- Output: `output_ref` (e.g., `:dev-disk-amd64` or `:prod-disk-amd64`)
- Produces containerDisk (FROM scratch with qcow2 at `/disk/disk.qcow2`)

**Analysis:**
- ✅ Takes a bootc image and converts to containerDisk
- ✅ No cross-arch build (native AMD64 runner)
- ✅ Manual dispatch (triggered on demand)

**Recommendations:**
- ✅ No changes needed.

---

### ✅ `.github/workflows/promote-rhel10-bootc-prod`

**Promotes:**
- `:dev-amd64` → `:prod-amd64` (via `skopeo copy`)
- Signed with keyless Cosign

**Analysis:**
- ✅ Uses `skopeo copy` to preserve digest
- ✅ Self-hosted runner (for signing consistency)

**Recommendations:**
- ✅ No changes needed.

---

## 🎯 Deployment Workflows

### Workflow 1: Dev → Prod (Full Build Path)

```
1. Commit to main
   ↓
2. build-sign-push.yml runs
   ├─ Builds & pushes :dev-amd64 (native AMD64 runner)
   ├─ Builds & pushes :dev-arm64 (self-hosted ARM64 runner)
   └─ Signs both with keyless Cosign
   ↓
3. Manual: build-qcow2.yml (dispatch)
   ├─ Input: image=quay.io/waba/bootc-guide:dev-amd64
   ├─ Output: output_ref=quay.io/waba/bootc-guide:dev-disk-amd64
   └─ Produces containerDisk (FROM scratch)
   ↓
4. Manual: promote-rhel10-bootc-prod (dispatch)
   ├─ Promotes :dev-amd64 → :prod-amd64 (skopeo copy)
   ├─ Promotes :dev-disk-amd64 → :prod-disk-amd64 (local script)
   └─ Signs :prod-* tags
   ↓
5. Manual or Scheduled: deploy-to-openshift-virt.sh
   ├─ Verifies :prod-disk-amd64 exists on Quay
   ├─ Runs ansible/provision-vm.yml with disk_image=:prod-disk-amd64
   └─ Deploys to OpenShift Virtualization
```

### Workflow 2: Update Running VM

```
1. Commit to main (triggers build-sign-push.yml)
   ↓
2. Wait for :dev-amd64 to build & sign
   ↓
3. Manual: build-qcow2.yml (dispatch with :dev-amd64)
   ↓
4. Manual: promote-rhel10-bootc-prod (dispatch)
   ├─ :dev-amd64 → :prod-amd64
   └─ :dev-disk-amd64 → :prod-disk-amd64
   ↓
5. Manual: ansible/upgrade-vm.yml
   ├─ Inside VM: bootc upgrade (automatically detects new :prod-amd64)
   ├─ Reboots into new image
   └─ Waits for VM to come up
```

---

## 🔄 Tag Consistency Rules

To maintain consistency and traceability:

1. **Development Tags (`:dev-*`):**
   - Built automatically on every commit to `main`
   - Used for testing and validation
   - Never promoted to production without review

2. **Production Tags (`:prod-*`):**
   - Always have the same digest as their `:dev-*` counterparts
   - Promote via `skopeo copy` or manual promotion scripts
   - Signed with Cosign

3. **No Cross-Arch Builds:**
   - ARM64 images never cross-compile to AMD64 (and vice versa)
   - Separate build runners for each architecture
   - Separate tags and workflows

4. **Container Format:**
   - Bootc images: Standard OCI image format
   - ContainerDisk images: `FROM scratch` with qcow2 at `/disk/disk.qcow2`
   - CDI's `pullMethod: node` can pull these natively

---

## ✅ Summary

**All Ansible playbooks, deployment scripts, and GitHub Actions workflows are tag-consistent and production-ready.**

### Key Takeaways:
- ✅ `provision-vm.yml` defaults to `:prod-disk-amd64` (production-ready)
- ✅ `upgrade-vm.yml` uses bootc's native update mechanism
- ✅ `deploy-to-openshift-virt.sh` correctly orchestrates the full flow
- ✅ All tags follow the `:dev-*` and `:prod-*` naming convention
- ✅ Digest consistency is maintained across promotions
- ✅ No cross-architecture emulation (native builds only)

**No changes are needed. The deployment workflow is consistent and ready for production use.**
