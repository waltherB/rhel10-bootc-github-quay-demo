# Demo script

## Pre-demo checklist

Run through this the night before and again 30 minutes before going on stage.

### Environment variables

The recommended approach is to create `scripts/demo-env.sh` (gitignored, never committed) with your values — copy `scripts/demo-env.sh.example` as a starting point. `scripts/demo-run.sh` sources it automatically at startup.

**ARCH SPLIT:** the ARM64 bootc image + qcow2 disk are built LOCALLY (native on the Mac) and used only for the local UTM VM (steps 2, 2b, 7b–8). The AMD64 bootc image + qcow2 disk are built REMOTELY by GitHub Actions (native on `ubuntu-latest` runners) and used only for OpenShift Virtualization on the x86_64 SNO cluster (step 9a). The two never cross paths — see [README.md](../README.md#architecture-split-arm64-local-vs-amd64-ci) for why.

```bash
# scripts/demo-env.sh — fill in your values (see scripts/demo-env.sh.example for the full set)

# ── Local (ARM64) — built natively on Mac, used for the UTM VM demo ──
export TARGET_PLATFORM_LOCAL="linux/arm64"
export IMAGE_ARM="quay.io/waba/bootc-guide:dev-arm64"
export DISK_IMAGE_ARM="quay.io/waba/bootc-guide:dev-disk-arm64"
export PROD_IMAGE_ARM="quay.io/waba/bootc-guide:prod-arm64"
export PROD_DISK_IMAGE_ARM="quay.io/waba/bootc-guide:prod-disk-arm64"

# ── Remote (AMD64) — built natively on GitHub-hosted ubuntu runners,
#    used for OpenShift Virtualization (x86_64 SNO cluster) ──
export TARGET_PLATFORM_REMOTE="linux/amd64"
export IMAGE_AMD="quay.io/waba/bootc-guide:dev-amd64"
export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:dev-disk-amd64"
export PROD_IMAGE_AMD="quay.io/waba/bootc-guide:prod-amd64"
export PROD_DISK_IMAGE_AMD="quay.io/waba/bootc-guide:prod-disk-amd64"

export VM_SSH="demo@<vm-ip>"              # set after VM is built and booted in UTM
export VM_SSH_KEY="${HOME}/.ssh/id_ed25519"

export SNO_API="https://api.waba-sno.adc.lan:6443"
export SNO_TOKEN="$(oc whoami -t 2>/dev/null || true)"

# Set to skip the AMD64 qcow2 rebuild when restarting at step 9a — the
# promote (:dev-disk-amd64 → :prod-disk-amd64) still runs, but is a fast
# skopeo copy, no rebuild.
# export DISK_IMAGE_AMD="${PROD_DISK_IMAGE_AMD}"

# Quay auth for Ansible — auto-generated from Podman auth file at startup
# export QUAY_DOCKER_CONFIG_B64="$(base64 < ~/.config/containers/auth.json)"
```

At startup `demo-run.sh` shows each variable and asks you to press ENTER to confirm (or type a new value to override). If `demo-env.sh` is sourced, all values are pre-populated.

### Restarting from a specific step

If a step fails during a demo, restart from that step without repeating earlier ones:

```bash
START_STEP=9a ./scripts/demo-run.sh
```

Valid step IDs: `1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b`

> Set `DISK_IMAGE_AMD` in `demo-env.sh` to skip the AMD64 containerDisk rebuild when restarting at step 9a — the promote (skopeo copy) will still run but is fast.

---

### Pre-demo prep — do the night before

These steps take too long to run on stage. Complete them beforehand.

#### Build the ARM64 qcow2 and the UTM VM

The UTM VM's live-update loop (steps 7a–8) tracks the shared, generic `:prod` tag that `promote-rhel10-bootc-prod` writes (see the presenter note under step 6 — the workflow doesn't currently produce an arch-suffixed `:prod-arm64`). So build a `:dev-arm64` first, then promote it to `:prod` before building the qcow2 from that:

```bash
# Build and push a known-good ARM64 image
IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-build.sh
IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-push.sh

# Promote it to the shared :prod tag (GitHub → Actions → promote-rhel10-bootc-prod →
# Run workflow, source_tag: dev-arm64) — or manually:
skopeo copy docker://quay.io/waba/bootc-guide:dev-arm64 docker://quay.io/waba/bootc-guide:prod

# Switch Podman machine to rootful (required for bootc-image-builder)
podman machine stop
podman machine set --rootful
podman machine start

export IMAGE_ARM="quay.io/waba/bootc-guide:prod"
./scripts/local-build-qcow2.sh      # produces output/qcow2/disk-arm.qcow2 (~5-10 min), native arm64, no emulation
```

`local-build-qcow2.sh` also wraps the qcow2 as a containerDisk and pushes it to Quay (`DISK_IMAGE_ARM`, default `:dev-disk-arm64` — override it if you want a distinct name here), but that push is only needed if something else consumes it — the UTM VM itself boots straight from the local `.qcow2` file.

> ⚠️ Because `:prod` is shared across architectures, don't promote an amd64 build to `:prod` between now and the live 7a–8 demo, or the ARM64 VM's next `bootc upgrade` will try to pull an amd64 manifest it can't run.

#### Build the AMD64 disk for OpenShift (for step 9a)

This runs remotely on a native amd64 GitHub-hosted runner — never locally, and never with `--platform` emulation. Kick it off the night before so it's ready when step 9a needs it:

```bash
gh workflow run build-qcow2.yml \
  --field image=quay.io/waba/bootc-guide:dev-amd64 \
  --field output_ref=quay.io/waba/bootc-guide:dev-disk-amd64

# watch it
gh run watch "$(gh run list --workflow=build-qcow2.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Then promote it to `:prod-disk-amd64` so step 9a only needs to provision, not rebuild:

```bash
SOURCE_DISK=quay.io/waba/bootc-guide:dev-disk-amd64 \
TARGET_DISK=quay.io/waba/bootc-guide:prod-disk-amd64 \
  ./scripts/local-promote-disk.sh
```

> You can also let step 4 of the live demo dispatch `build-qcow2.yml` in the background and let step 9a promote it live. The pre-demo run above is only needed if you want `:prod-disk-amd64` already in place before the demo starts.

#### Import into UTM and boot

1. Open UTM → **+** → **Virtualize** → **Other**
2. Import `output/qcow2/disk-arm.qcow2` as the boot drive
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
- [ ] `gh auth status` — GitHub CLI is authenticated (used to dispatch `build-qcow2.yml` in step 4)
- [ ] `cat ~/.ssh/id_ed25519.pub` — SSH public key exists (used by Ansible and cloud-init)
- [ ] Font size in terminal cranked up for the back row
- [ ] Terminal window maximised on the presenter screen

#### GitHub

- [ ] Repo is public (or audience has access)
- [ ] Secrets set: `RH_REGISTRY_USERNAME`, `RH_REGISTRY_PASSWORD`, `QUAY_USERNAME`, `QUAY_TOKEN`, `RHSM_ORG`, `RHSM_ACTIVATION_KEY`
- [ ] Variable set: `QUAY_IMAGE=quay.io/waba/bootc-guide` (used by `promote-prod.yml`)
- [ ] Self-hosted ARM64 runner online (`build-sign-push.yml`'s `build-arm64` job) and self-hosted runner online (`promote-prod.yml`)
- [ ] A passing workflow run already exists for `build-sign-push.yml` — shows the audience what a green build looks like
- [ ] Browser tab open on GitHub Actions, ready to show

#### Quay

- [ ] `quay.io/waba/bootc-guide` repository exists and is readable
- [ ] `:dev-arm64` and `:dev-amd64` tags are present
- [ ] `:prod` tag is present and points at the **ARM64** digest (see the ⚠️ note in pre-demo prep — `promote-rhel10-bootc-prod` writes a single shared `:prod` tag, not arch-suffixed ones)
- [ ] `:dev-disk-amd64` and `:prod-disk-amd64` tags are present (built during pre-demo prep)
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
- [ ] `:prod-disk-amd64` (or whatever `DISK_IMAGE_AMD`/`PROD_DISK_IMAGE_AMD` resolves to) is present on Quay — built by `build-qcow2.yml`, see pre-demo prep above
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
- GitHub Actions workflows — build/sign/push, build-qcow2, promote
- Quay image — `:dev-arm64`/`:dev-amd64` tags, and a shared `:prod` tag

### 2. Local build on Mac M4

Native arm64 build, no cross-compilation, no emulation — the amd64 image is a completely separate build done by GitHub Actions in step 4/5.

```bash
export IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64
export TARGET_PLATFORM_LOCAL=linux/arm64
./scripts/local-build.sh
```

### 2b. Build the ARM64 qcow2 disk locally (for the UTM VM)

```bash
export IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64
export DISK_IMAGE_ARM=quay.io/waba/bootc-guide:dev-disk-arm64
./scripts/local-build-qcow2.sh
```

`bootc-image-builder` runs natively arm64-on-arm64 here — no emulation. This qcow2 is only ever used to (re)provision the local UTM VM; OpenShift always gets the separate amd64 disk from GitHub Actions in step 9a.

### 3. Smoke test the image as a container

```bash
IMAGE=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-test.sh
```

### 4. Push and sign the ARM64 image — then kick off the AMD64 build in the background

```bash
IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-push.sh          # push :dev-arm64 to Quay
IMAGE=quay.io/waba/bootc-guide:dev-arm64 ./scripts/local-sign-keyless.sh      # sign with keyless Cosign (OIDC)
```

Then push (or trigger) the change that starts the GitHub Actions CI pipeline (`build-sign-push.yml`) building `:dev-amd64` natively on a GitHub-hosted runner, and dispatch the amd64 containerDisk conversion in the background so it runs in parallel with steps 5–8:

```bash
gh workflow run build-qcow2.yml \
  --field image=quay.io/waba/bootc-guide:dev-amd64 \
  --field output_ref=quay.io/waba/bootc-guide:dev-disk-amd64
```

**Talking point:** `:dev-disk-amd64` is a `FROM scratch` container image with the qcow2 at `/disk/disk.qcow2`. CDI's registry importer understands this format natively — unlike the bootc imagemode OCI format which caused `Failed to find VM disk image file in the container image`. It's built entirely on a native amd64 GitHub-hosted runner, deliberately without a `--platform` flag on `podman run` — even a same-arch `--platform` flag routes through Podman's cross-arch code path, which is what previously caused a persistent `no such container` error.

### 5. GitHub Actions CI pipeline

Show `build-sign-push.yml` running:

- build AMD64 image natively on the GitHub-hosted runner (and ARM64 on the self-hosted runner)
- push `:dev-amd64` / `:dev-arm64` to Quay (only `:dev-*` on a normal push; `:v*` tags only on a git tag)
- cosign sign + verify

Point out that the amd64 containerDisk conversion kicked off in step 4 (`build-qcow2.yml`) is running in parallel on a separate native-amd64 runner.

### 6. Promote `:dev-amd64` → `:prod`

Run `promote-rhel10-bootc-prod` workflow manually from GitHub Actions with `source_tag: dev-amd64`.
`skopeo copy` copies by digest — no rebuild, what was tested is what goes to prod.

> **Presenter note:** the workflow currently always writes to the literal `:prod` tag, not `:prod-amd64` — `demo-run.sh`'s `PROD_IMAGE_AMD` default (`:prod-amd64`) won't actually exist on Quay after running this workflow as-is. Either retag `:prod` → `:prod-amd64` with `skopeo copy` right after, or set `PROD_IMAGE_AMD` in `demo-env.sh` to `...:prod` to match what the workflow really produces. Worth calling out live if you're demoing this end-to-end.

### 7a. Make a visible change

```bash
echo "RHEL 10 Image Mode Demo v2 – updated $(date +%F)" > files/motd
git add files/motd
git commit -m "chore: bump motd to v2 for live update demo"
git push
```

The push triggers `build-sign-push.yml`, which rebuilds **both** `:dev-arm64` and `:dev-amd64`. For this VM-update demo you only need the ARM64 side: once it's green, run `promote-rhel10-bootc-prod` with `source_tag: dev-arm64` (not the workflow's default `dev` — that tag doesn't exist anymore) to update the shared `:prod` tag.

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
  └── Actions: build-arm64 job → push :dev-arm64
        └── promote-rhel10-bootc-prod (source_tag: dev-arm64): skopeo copy :dev-arm64 → :prod (same digest)
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

This path uses only the **AMD64** image/disk — the x86_64 SNO cluster can't run arm64, so it never touches the `:prod` tag the UTM VM tracks.

#### 9a. Promote `:dev-disk-amd64` → `:prod-disk-amd64` and provision the VM

```bash
oc login "${SNO_API}" --token="${SNO_TOKEN}" --insecure-skip-tls-verify

# Promote the containerDisk — same digest, new tag, no rebuild
SOURCE_DISK=quay.io/waba/bootc-guide:dev-disk-amd64 \
TARGET_DISK=quay.io/waba/bootc-guide:prod-disk-amd64 \
  ./scripts/local-promote-disk.sh   # skopeo copy

# Provision the VM on SNO
ansible-playbook ansible/provision-vm.yml \
  -e disk_image=quay.io/waba/bootc-guide:prod-disk-amd64 \
  -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub)\""
```

**Talking point:** The disk promote mirrors the OS image promote in step 6 — same principle: what was tested as `:dev-disk-amd64` is exactly what runs as `:prod-disk-amd64`. No rebuild.

This assumes `:dev-disk-amd64` already exists — either built ahead of time in pre-demo prep, or by the background `build-qcow2.yml` dispatch from step 4 (check `disk-build.log` or the iTerm tail window).

Ansible creates:
- `bootc-vms` namespace with pod-security labels
- Quay pull secret (`quay-cdi-pull-secret`) for CDI
- ServiceAccount + RBAC
- `DataVolume` (CDI pulls `:prod-disk-amd64` from Quay via `registry` source, `pullMethod: node`)
- `VirtualMachine` with cloud-init SSH key injection

Watch it start in **OpenShift console → Virtualization → VirtualMachines**.

**Full flow:**
```
:dev-amd64  (bootc OCI, GitHub Actions)      →  push :dev-amd64        (step 4/5)
:dev-disk-amd64  (containerDisk, GH Actions) →  push :dev-disk-amd64   (step 4, background)
  │                                                  │
  └── promote :dev-amd64 → :prod (step 6)            └── promote :dev-disk-amd64 → :prod-disk-amd64 (step 9a)
                                                              │
                                     CDI imports :prod-disk-amd64 → PVC → VirtualMachine
```

> Note: step 6 promotes the AMD64 *OS* image to the same shared `:prod` tag the ARM64 UTM VM tracks (see the presenter note under step 6). It doesn't affect the OpenShift VM, which only ever reads `:prod-disk-amd64` — but don't run both the UTM live-update demo (7a–8) and this OpenShift demo back-to-back without re-checking which digest `:prod` currently points to.

#### 9b. Upgrade the VM

After promoting a new `:prod-amd64`-equivalent build (i.e. rebuilding `:dev-amd64` and promoting its disk to `:prod-disk-amd64` again — the running VM's OS image itself is pulled via `bootc upgrade` from whatever it was originally provisioned with):

```bash
ansible-playbook ansible/upgrade-vm.yml
```

The playbook connects via `virtctl ssh`, runs `bootc upgrade`, reboots, waits, and prints the new digest.

#### GitOps alternative

Apply the KubeVirt manifests directly:

```bash
oc apply -f gitops/openshift-virt/
```

> `gitops/openshift-virt/vm.yaml` currently hardcodes `quay.io/waba/bootc-guide:prod` as the DataVolume source — update it to `:prod-disk-amd64` (or your resolved `PROD_DISK_IMAGE_AMD`) before using this path, to match what `ansible/provision-vm.yml` actually provisions.
