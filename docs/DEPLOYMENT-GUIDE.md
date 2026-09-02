# OpenShift Virtualization Deployment Guide

This guide walks you through deploying the RHEL 10 bootc AMD64 image to OpenShift Virtualization (KubeVirt) using the automated deployment script and Ansible playbooks.

---

## 📋 Prerequisites

Before running the deployment, ensure you have:

### Local Environment
- **oc CLI:** Authenticated to your SNO (Single Node OpenShift) cluster
  ```bash
  oc login https://api.your-cluster.example.com --token=<token>
  oc cluster-info  # Verify connectivity
  ```

- **Podman/Docker:** Authenticated to Quay.io
  ```bash
  podman login quay.io
  ```

- **Ansible:** Installed with Kubernetes collections
  ```bash
  pip install ansible kubernetes
  ansible-galaxy collection install -r ansible/requirements.yml
  ```

### Quay Registry
- **AMD64 bootc image:** `:dev-amd64` or `:prod-amd64`
- **AMD64 containerDisk image:** `:dev-disk-amd64` or `:prod-disk-amd64` (built by `build-sign-push.yml` on GitHub Actions)
  - **Note:** The containerDisk is a `FROM scratch` OCI image with the qcow2 at `/disk/disk.qcow2`. It's built by the `.github/workflows/build-sign-push.yml` GitHub Actions workflow on a native AMD64 runner.

### Cluster Requirements
- OpenShift Virtualization (KubeVirt) enabled on your SNO cluster
- CDI (Containerized Data Importer) for importing VM disks
- A storage class for PVCs (default: `lvms-vg1`)

---

## 🚀 Quick Start

### 1. Set Environment Variables (Optional)

Create `scripts/demo-env.sh` (or set these in your shell):

```bash
export IMAGE_AMD="quay.io/waba/bootc-guide:dev-amd64"
export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:dev-disk-amd64"
export VM_NAME="rhel10-bootc-demo"
export VM_NAMESPACE="bootc-vms"
export VM_CORES="2"
export VM_MEMORY="2Gi"
export VM_DISK_SIZE="60Gi"
export VM_STORAGE_CLASS="lvms-vg1"
```

### 2. Run the Deployment Script

```bash
./scripts/deploy-to-openshift-virt.sh
```

**Or with explicit flags:**

```bash
./scripts/deploy-to-openshift-virt.sh \
  --image-ref quay.io/waba/bootc-guide:prod-amd64 \
  --disk-ref quay.io/waba/bootc-guide:prod-disk-amd64 \
  --vm-name rhel10-bootc-demo \
  --namespace bootc-vms
```

### 3. Wait for VM to Come Up

The script will:
1. Verify images are available on Quay
2. Run the Ansible provisioning playbook
3. Wait for the DataVolume to import (5-10 minutes)
4. Display the VM's IP address and SSH connection info

Monitor progress:

```bash
# Watch VM status
oc get vmi -n bootc-vms -w

# Watch DataVolume import progress
oc get dv -n bootc-vms -w

# Check CDI importer logs
oc logs -n bootc-vms -l app.kubernetes.io/component=importer -f
```

### 4. Connect to the VM

Once the VM is running, SSH in:

```bash
oc get vmi -n bootc-vms  # Get IP address
ssh demo@<IP>
```

Inside the VM, check the bootc status:

```bash
sudo bootc status
```

---

## 🔄 Understanding the Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Step 1: deploy-to-openshift-virt.sh (Orchestrator)        │
│  ├─ Verify prerequisites (oc, ansible, podman auth)        │
│  ├─ Verify images exist on Quay                            │
│  └─ Call Ansible playbook → Stage 2                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 2: provision-vm.yml (Ansible Playbook)               │
│  ├─ Create namespace with pod-security labels              │
│  ├─ Extract Quay credentials from ~/.docker/config.json    │
│  ├─ Create Kubernetes Secrets (CDI pull auth)              │
│  ├─ Create ServiceAccount, RBAC Role, RoleBinding           │
│  ├─ Delete existing VM/DataVolume/PVC (if any)             │
│  ├─ Create DataVolume (CDI importer starts here)           │
│  ├─ Create VirtualMachine object                           │
│  ├─ Wait for DataVolume import to complete                 │
│  └─ Wait for VM to reach Running state                     │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 3: deploy-to-openshift-virt.sh (Post-Deploy)         │
│  ├─ Fetch VM IP address                                    │
│  ├─ Display SSH connection info                            │
│  └─ Print next steps                                       │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

**Containerization & Distribution:**
- **AMD64 bootc image** (`quay.io/waba/bootc-guide:dev-amd64` or `:prod-amd64`)
  - The actual RHEL 10 bootc OS image built by `.github/workflows/build-sign-push.yml`.
  - This is pushed and signed by GitHub Actions on every commit to `main`.
  - Promotion to `:prod-amd64` happens via `promote-rhel10-bootc-prod` workflow (same digest, no rebuild).

- **AMD64 containerDisk image** (`quay.io/waba/bootc-guide:dev-disk-amd64` or `:prod-disk-amd64`)
  - A `FROM scratch` OCI image containing the qcow2 at `/disk/disk.qcow2`.
  - Built by `.github/workflows/build-sign-push.yml` (push to `main` or manual dispatch, native AMD64 runner).
  - Promotion to `:prod-disk-amd64` happens via `scripts/local-promote-disk.sh` (skopeo copy, same digest).

**Kubernetes Resources:**
- **Namespace:** `bootc-vms` (or custom via `VM_NAMESPACE`)
  - Labeled with `pod-security.kubernetes.io/enforce: privileged` for VirtualMachine pod security.

- **Secret:** `quay-cdi-pull-secret`
  - Extracts credentials from `~/.docker/config.json` for Quay.io authentication.
  - Used by CDI to pull the containerDisk image.

- **DataVolume:** `${VM_NAME}-dv`
  - CDI resource that imports the qcow2 disk from the containerDisk OCI image.
  - Uses `pullMethod: node` so the cluster node's CRI directly pulls from Quay (no HTTP server needed).

- **VirtualMachine:** `${VM_NAME}`
  - KubeVirt VM definition.
  - Machine type: `pc-q35-rhel9.4.0` (AMD64 machine type, required for x86_64 SNO).
  - Firmware: UEFI (bootc/RHEL 10 images are GPT/EFI-only; BIOS would hang).
  - Cloud-init: Injects SSH public key (`~/.ssh/id_ed25519.pub`) and installs `qemu-guest-agent`.

---

## 📊 Monitoring & Troubleshooting

### Check VM Status

```bash
# List all VMs
oc get vm -n bootc-vms

# List running VirtualMachineInstances (the actual running pod)
oc get vmi -n bootc-vms

# Get detailed VM info
oc describe vm rhel10-bootc-demo -n bootc-vms
oc describe vmi rhel10-bootc-demo -n bootc-vms
```

### Check DataVolume Import Progress

```bash
# List DataVolumes
oc get dv -n bootc-vms

# Watch DV progress
oc get dv -n bootc-vms -o wide -w

# Get detailed DV status
oc describe dv rhel10-bootc-demo-dv -n bootc-vms

# View CDI importer pod logs
oc logs -n bootc-vms -l app.kubernetes.io/component=importer -f
```

### Common Issues & Solutions

#### 1. **DataVolume stuck in "Importing" state**
- **Cause:** CDI importer pod unable to pull the containerDisk from Quay.
- **Solution:**
  ```bash
  # Check importer pod logs
  oc logs -n bootc-vms -l app.kubernetes.io/component=importer
  
  # Verify pull secret was created
  oc get secret -n bootc-vms quay-cdi-pull-secret
  
  # Verify credentials in the secret
  oc get secret quay-cdi-pull-secret -n bootc-vms -o yaml
  ```

#### 2. **VM won't start / "Booting from Hard Disk..." hangs**
- **Cause:** Machine type is BIOS (SeaBIOS); bootc images are GPT/EFI-only.
- **Solution:** The Ansible playbook sets `machine.type: pc-q35-rhel9.4.0` and `firmware.bootloader.efi: {}`. If this doesn't work, verify the VM definition:
  ```bash
  oc get vm rhel10-bootc-demo -n bootc-vms -o yaml | grep -A 5 "machine:\|firmware:"
  ```

#### 3. **Cannot SSH to VM**
- **Cause:** SSH key not injected via cloud-init, or VM IP not ready.
- **Solution:**
  ```bash
  # Get VM console
  virtctl console rhel10-bootc-demo -n bootc-vms
  
  # Check cloud-init logs inside VM
  sudo tail -100 /var/log/cloud-init-output.log
  
  # Verify SSH key was added
  cat ~/.ssh/authorized_keys
  ```

#### 4. **Image pull fails: "no such image"**
- **Cause:** Image doesn't exist on Quay or credentials are wrong.
- **Solution:**
  ```bash
  # Verify image exists
  podman inspect quay.io/waba/bootc-guide:dev-disk-amd64
  
  # Re-authenticate to Quay
  podman login quay.io
  
  # Verify ~/.docker/config.json is readable
  cat ~/.docker/config.json
  ```

---

## 🔄 VM Lifecycle Operations

### Upgrade VM to New OS Image

After promoting a new `:prod-amd64` or `:prod-disk-amd64` image, upgrade the running VM:

```bash
ansible-playbook ansible/upgrade-vm.yml \
  -e vm_name=rhel10-bootc-demo \
  -e vm_namespace=bootc-vms
```

This playbook:
1. Checks current bootc status
2. Checks if an upgrade is available
3. Stages the new image with `bootc upgrade`
4. Reboots into the new image
5. Waits for VM to come back up

### Delete the VM

To clean up:

```bash
# Delete via oc
oc delete vm rhel10-bootc-demo -n bootc-vms

# (Optional) Delete the namespace
oc delete namespace bootc-vms
```

---

## 🎯 Integration with CI/CD

The deployment workflow fits into a larger CI/CD pipeline:

### Build Phase (GitHub Actions)
1. **`.github/workflows/build-sign-push.yml`** (push to `main` or manual dispatch)
  - Builds and pushes `:dev-amd64` and `:dev-disk-amd64` on a native AMD64 runner
  - Signs with keyless Cosign

### Promotion Phase (GitHub Actions)
2. **`promote-rhel10-bootc-prod`** (manual dispatch)
   - Promotes `:dev-amd64` → `:prod-amd64` (same digest, skopeo copy)
   - Promotes `:dev-disk-amd64` → `:prod-disk-amd64` (same digest, skopeo copy)

### Deployment Phase (Local or CI)
4. **`./scripts/deploy-to-openshift-virt.sh`** (manual or scheduled)
   - Deploys `:prod-disk-amd64` to OpenShift Virtualization

### Update Phase (Local or CI)
5. **`ansible/upgrade-vm.yml`** (manual or scheduled)
   - Upgrades running VM to latest `:prod-amd64`

---

## 📝 Tag Consistency

The Ansible playbooks and deployment script are designed to work with consistent tagging:

| Phase | Image | Tag | Source |
|-------|-------|-----|--------|
| **Development** | AMD64 bootc | `:dev-amd64` | `.github/workflows/build-sign-push.yml` |
| **Development** | AMD64 containerDisk | `:dev-disk-amd64` | `.github/workflows/build-sign-push.yml` |
| **Production** | AMD64 bootc | `:prod-amd64` | `promote-rhel10-bootc-prod` (same digest) |
| **Production** | AMD64 containerDisk | `:prod-disk-amd64` | `scripts/local-promote-disk.sh` (same digest) |

**Key Principle:** `:prod-*` tags always have the same digest as their `:dev-*` counterparts (no rebuild, no emulation, full traceability).

---

## 📖 Related Documentation

- [Speaker Notes (DA)](speaker-notes-da.md) — Presentation guide for the demo
- [OpenShift Virtualization Extension](openShift-virtualization-extension.md) — Detailed technical deep dive
- [Live Demo Checklist](live-demo-checklist.md) — Checklist for demo day
- [README](../README.md) — Project overview and architecture
