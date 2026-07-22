# Demo script

## Pre-demo checklist

Run through this the night before and again 30 minutes before going on stage.

### Environment variables

The recommended approach is to create `scripts/demo-env.sh` (gitignored, never committed) with your values. `scripts/demo-run.sh` sources it automatically at startup:

```bash
# scripts/demo-env.sh — fill in your values
export IMAGE="quay.io/waba/bootc-guide:dev"
export TARGET_PLATFORM="linux/arm64"

export VM_SSH="demo@<vm-ip>"              # set after VM is built and booted in UTM
export VM_SSH_KEY="${HOME}/.ssh/id_ed25519"

export SNO_API="https://api.waba-sno.adc.lan:6443"
export SNO_TOKEN="$(oc whoami -t 2>/dev/null || true)"

# Set to skip the qcow2 rebuild when restarting at step 9a
# export DISK_IMAGE="quay.io/waba/bootc-guide:prod-disk"

# Quay auth for Ansible — auto-generated from Podman auth file at startup
# export QUAY_DOCKER_CONFIG_B64="$(base64 < ~/.config/containers/auth.json)"
```

A template is at `scripts/demo-env.sh` — just fill in your values.

At startup `demo-run.sh` shows each variable and asks you to press ENTER to confirm (or type a new value to override). If `demo-env.sh` is sourced, all values are pre-populated.

### Restarting from a specific step

If a step fails during a demo, restart from that step without repeating earlier ones:

```bash
START_STEP=9a ./scripts/demo-run.sh
```

Valid step IDs: `1 2 3 4 5 6 7a 7b 7c 7d 8 9a 9b`

> Set `DISK_IMAGE` in `demo-env.sh` to skip the containerDisk rebuild when restarting at step 9a — the promote (skopeo copy) will still run but is fast.

---

### Pre-demo prep — do the night before

These steps take too long to run on stage. Complete them beforehand.

#### Build the qcow2 and the UTM VM

```bash
# Switch Podman machine to rootful (required for bootc-image-builder)
podman machine stop
podman machine set --rootful
podman machine start

export IMAGE="quay.io/waba/bootc-guide:prod"
./scripts/local-qcow2.sh      # produces output/qcow2/disk.qcow2 (~5-10 min)
```

#### Push the containerDisk to Quay (for OpenShift step)

```bash
# Still in rootful mode — do this immediately after local-qcow2.sh
./scripts/local-push-disk.sh  # pushes :prod-disk to Quay
```

> You can also let step 4 of the demo build `:dev-disk` and let step 9a promote it to `:prod-disk`. The pre-demo push is only needed if you want a `:prod-disk` already in place before the demo starts.

#### Import into UTM and boot

1. Open UTM → **+** → **Virtualize** → **Other**
2. Import `output/qcow2/disk.qcow2` as the boot drive
3. Set architecture to **ARM64 (aarch64)**
4. Set RAM to at least **2 GiB**, CPU to **2 cores**
5. Boot the VM and log in as `demo` / `redhat`
6. Verify the VM is tracking `:prod`:
   ```bash
   vm-status
   ```
7. Note the IP address:
   ```bash
   ip addr show | grep 'inet '
   # or on your Mac:
   arp -a | grep utm
   ```

#### Switch Podman machine back to rootless

```bash
podman machine stop
podman machine set --rootless
podman machine start
```

---

### Day-of checklist

#### Mac

- [ ] `podman machine start` — Podman machine is running (rootless for normal use)
- [ ] `podman login registry.redhat.io` — Red Hat registry session active
- [ ] `podman login quay.io` — Quay session active
- [ ] `cosign version` — cosign is installed (`brew install cosign`)
- [ ] `skopeo --version` — skopeo is installed (`brew install skopeo`)
- [ ] `cat ~/.ssh/id_ed25519.pub` — SSH public key exists (used by Ansible and cloud-init)
- [ ] Font size in terminal cranked up for the back row
- [ ] Terminal window maximised on the presenter screen

#### GitHub

- [ ] Repo is public (or audience has access)
- [ ] Secrets set: `RH_REGISTRY_USERNAME`, `RH_REGISTRY_PASSWORD`, `QUAY_USERNAME`, `QUAY_TOKEN`, `RHSM_ORG`, `RHSM_ACTIVATION_KEY`
- [ ] Variables set: `QUAY_IMAGE=quay.io/waba/bootc-guide`, `TARGET_PLATFORM=linux/arm64`
- [ ] A passing workflow run already exists — shows the audience what a green build looks like
- [ ] Browser tab open on GitHub Actions, ready to show

#### Quay

- [ ] `quay.io/waba/bootc-guide` repository exists and is readable
- [ ] `:dev` and `:prod` tags are present
- [ ] `:dev-disk` and `:prod-disk` tags are present (built during pre-demo prep)
- [ ] Browser tab open on the repository tags page

#### UTM VM

- [ ] VM is booted in UTM
- [ ] VM is reachable: `ssh demo@<vm-ip> vm-status`
- [ ] `Booted image` in `vm-status` output shows `:prod`
- [ ] httpd is responding: `curl http://<vm-ip>`
- [ ] IP is set in `scripts/demo-env.sh` as `VM_SSH="demo@<vm-ip>"`

#### OpenShift SNO

- [ ] Cluster is up: `oc get nodes`
- [ ] OpenShift Virtualization operator is installed and healthy: `oc get csv -n openshift-cnv`
- [ ] CDI operator is healthy: `oc get cdi -n cdi`
- [ ] `bootc-vms` namespace exists with correct pod-security labels:
  ```bash
  oc new-project bootc-vms 2>/dev/null || echo "already exists"
  oc label namespace bootc-vms \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite
  ```
- [ ] Quay pull secret exists in the namespace (Ansible creates `quay-cdi-pull-secret` automatically)
- [ ] StorageClass supports `ReadWriteOnce`:
  ```bash
  oc get storageclass
  ```
  Note the name (e.g. `lvms-vg1`) — must match `vm_storage_class` in `ansible/provision-vm.yml`
- [ ] `virtctl version` — virtctl CLI installed
- [ ] `ansible --version` and `ansible-galaxy collection list | grep kubevirt` — ready
- [ ] Browser tab open: OpenShift console → Virtualization → VirtualMachines
- [ ] SNO token ready: `oc whoami -t`
- [ ] Verify API URL includes port 6443: `https://api.<cluster>:6443`

#### Final check

Edit `scripts/demo-env.sh` with your actual values, then do a full dry run:

```bash
./scripts/demo-run.sh
```

The script sources `demo-env.sh` automatically, shows each variable for confirmation, and starts. **Do a full dry run the night before** — skip the git push step to avoid burning a CI run. For the OpenShift steps, use `START_STEP=9a` to jump straight there.

---

## Live demo steps

### 1. Show the repo

- `Containerfile` — the OS defined as code
- GitHub Actions workflow — build, test, sign, push
- Quay image — `:dev` and `:prod` tags

### 2. Local build on Mac M4

```bash
export IMAGE=quay.io/waba/bootc-guide:dev
export TARGET_PLATFORM=linux/arm64
./scripts/local-build.sh
```

### 3. Smoke test the image as a container

```bash
./scripts/local-test.sh
```

### 4. Push, sign — and build the containerDisk

```bash
./scripts/local-push.sh           # push :dev to Quay
./scripts/local-sign-keyless.sh   # sign with keyless Cosign (OIDC)
```

Then build the qcow2 and containerDisk. This is done here so step 9a only needs a fast `skopeo copy` promote — no rebuild on stage.

> Requires rootful Podman machine (~5-10 min on first run):

```bash
./scripts/local-qcow2.sh          # OCI image → output/qcow2/disk.qcow2
./scripts/local-push-disk.sh      # wrap qcow2 → FROM-scratch OCI → push :dev-disk
```

**Talking point:** `:dev-disk` is a `FROM scratch` container image with the qcow2 at `/disk/disk.qcow2`. CDI's registry importer understands this format natively — unlike the bootc imagemode OCI format which caused `Failed to find VM disk image file in the container image`.

### 5. GitHub Actions CI pipeline

Push a commit to GitHub and show the workflow:

- build
- smoke test
- push `:dev` to Quay (only `:dev` on a normal push; `:v*` tags only on a git tag)
- cosign sign + verify

### 6. Promote `:dev` → `:prod`

Run `promote-rhel10-bootc-prod` workflow manually from GitHub Actions.
`skopeo copy` copies by digest — no rebuild, what was tested is what goes to prod.

### 7a. Make a visible change

```bash
echo "RHEL 10 Image Mode Demo v2 – updated $(date +%F)" > files/motd
git add files/motd
git commit -m "chore: bump motd to v2 for live update demo"
git push
```

### 7b. Check the VM before the update

```bash
vm-status   # run inside the UTM VM
```

Note the booted digest — this is the old version.

### 7c. Apply the update

```bash
vm-upgrade  # run inside the UTM VM – pulls new :prod layers and reboots
```

### 7d. Verify after reboot

```bash
vm-status   # digest and motd should both show the new version
```

**What happened under the hood:**
```
git push
  └── Actions: build → test → push :dev
        └── promote: skopeo copy :dev → :prod (same digest)
              └── VM: bootc upgrade pulls new :prod layers
                    └── systemctl reboot → boots new OSTree deployment
                          └── previous deployment retained as rollback target
```

### 8. Rollback

```bash
# run inside the UTM VM
sudo bootc rollback
sudo systemctl reboot
```

After reboot, `vm-status` shows the previous digest is restored.

---

### 9. OpenShift Virtualization – provision and upgrade VMs with Ansible

Instead of UTM, VMs run as Kubernetes `VirtualMachine` objects on SNO, booting from the same disk image stored on Quay.

**Why not use the bootc OCI image directly?**
CDI's registry importer expects a KubeVirt containerDisk format (`FROM scratch` + `/disk/disk.qcow2`). The bootc imagemode OCI format stores layers differently, causing:
```
Failed to find VM disk image file in the container image
```
Solution: convert to qcow2 with `bootc-image-builder` and package as a containerDisk.

#### 9a. Promote `:dev-disk` → `:prod-disk` and provision the VM

```bash
# Promote the containerDisk — same digest, new tag, no rebuild
./scripts/local-promote-disk.sh   # :dev-disk → :prod-disk via skopeo copy

# Provision the VM on SNO
ansible-playbook ansible/provision-vm.yml \
  -e disk_image=quay.io/waba/bootc-guide:prod-disk \
  -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub)\""
```

**Talking point:** The disk promote mirrors the OS image promote in step 6 — same principle: what was tested as `:dev-disk` is exactly what runs as `:prod-disk`. No rebuild.

Ansible creates:
- `bootc-vms` namespace with pod-security labels
- Quay pull secret (`quay-cdi-pull-secret`) for CDI
- ServiceAccount + RBAC
- `DataVolume` (CDI pulls `:prod-disk` from Quay via `registry` source, `pullMethod: node`)
- `VirtualMachine` with cloud-init SSH key injection

Watch it start in **OpenShift console → Virtualization → VirtualMachines**.

**Full flow:**
```
:dev  (bootc OCI)       →  push :dev
:dev-disk  (containerDisk) →  push :dev-disk    (step 4)
  │                              │
  └──── promote :dev → :prod     └──── promote :dev-disk → :prod-disk   (step 9a)
                                              │
                             CDI imports :prod-disk → PVC → VirtualMachine
```

#### 9b. Upgrade the VM

After promoting a new `:prod` image:

```bash
ansible-playbook ansible/upgrade-vm.yml
```

The playbook connects via `virtctl ssh`, runs `bootc upgrade`, reboots, waits, and prints the new digest.

#### GitOps alternative

Apply the KubeVirt manifests directly:

```bash
oc apply -f gitops/openshift-virt/
```
