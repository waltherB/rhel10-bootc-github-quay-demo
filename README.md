# RHEL 10 Image Mode Demo – GitHub Actions + Quay + OpenShift Virtualization

Demo repo for building, signing and deploying a RHEL 10 bootc / Image Mode image.

For a full step-by-step walkthrough — local build, CI pipeline, VM provisioning, live OS update, and rollback — see the [demo script](docs/demo-script.md).

Target setup:

- MacBook Pro M4
- Podman + Podman Desktop
- UTM for RHEL 10 VMs
- Quay.io as image registry
- GitHub as source repo and CI
- OpenShift Virtualization (KubeVirt) for VM lifecycle on SNO
- Ansible for VM provisioning and upgrades

> Important: replace `quay.io/waba/bootc-guide` with your actual Quay namespace/repository throughout.

## Quick local flow

```bash
podman login registry.redhat.io
podman login quay.io
cosign login quay.io -u <your-quay-username> -p <your-quay-token>

export IMAGE=quay.io/waba/bootc-guide:dev

./scripts/local-build.sh          # build OCI bootc image
./scripts/local-test.sh           # smoke test as container
./scripts/local-push.sh           # push :dev to Quay
./scripts/local-sign-keyless.sh   # sign with keyless Cosign
./scripts/local-qcow2.sh          # convert to qcow2 (for UTM or OpenShift)
./scripts/local-push-disk.sh      # wrap qcow2 as containerDisk, push :dev-disk
```

> **Note:** `cosign` uses its own credential store — run `cosign login` separately from `podman login`.  
> Podman auth is stored in `~/.config/containers/auth.json` on macOS.

Import `output/qcow2/disk.qcow2` in UTM to create a local ARM VM.

## Tagging strategy

| Tag | Produced by | Content |
|---|---|---|
| `:dev` | Every push to `main` | Latest built OCI bootc image |
| `:dev-disk` | `local-push-disk.sh` after `:dev` push | KubeVirt containerDisk for CDI import |
| `:prod` | `promote-rhel10-bootc-prod` workflow | Promoted from `:dev` (same digest) |
| `:prod-disk` | `local-promote-disk.sh` | Promoted from `:dev-disk` (same digest) |
| `:v1.0.0` | `git tag v1.0.0` | Immutable release |

SHA traceability is preserved via the image digest — no `dev-<sha>` tags needed.

## GitHub Actions

Create these GitHub repository secrets:

- `RH_REGISTRY_USERNAME`
- `RH_REGISTRY_PASSWORD`
- `QUAY_USERNAME`
- `QUAY_TOKEN`
- `RHSM_ORG`
- `RHSM_ACTIVATION_KEY`

Create these GitHub repository variables:

- `QUAY_IMAGE=quay.io/waba/bootc-guide`
- `TARGET_PLATFORM=linux/arm64` for Mac M4 / UTM ARM demo

For GitHub-hosted runners, Linux runners are normally x86_64. For an ARM64 image that matches a Mac M4 / UTM ARM VM, use a self-hosted ARM64 runner or build locally on the Mac.

## OpenShift Virtualization

The `ansible/` and `gitops/openshift-virt/` directories extend the demo to a Single Node OpenShift cluster with OpenShift Virtualization.

CDI (Containerized Data Importer) imports the VM disk from Quay using a **KubeVirt containerDisk** image — a `FROM scratch` OCI image with the qcow2 at `/disk/disk.qcow2`. This avoids the imagemode OCI format limitation in CDI's registry importer.

```bash
# Install dependencies
pip install ansible kubernetes
ansible-galaxy collection install -r ansible/requirements.yml

# Build the containerDisk and push to Quay
export IMAGE=quay.io/waba/bootc-guide:prod
./scripts/local-qcow2.sh          # produces output/qcow2/disk.qcow2
./scripts/local-push-disk.sh      # pushes :prod-disk to Quay

# Provision VM on SNO
ansible-playbook ansible/provision-vm.yml \
  -e disk_image=quay.io/waba/bootc-guide:prod-disk \
  -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub)\""

# Upgrade VM after a new :prod image is promoted
ansible-playbook ansible/upgrade-vm.yml
```

See [section 9 of the demo script](docs/demo-script.md#9-openshift-virtualization--provision-and-upgrade-vms-with-ansible) for the full walkthrough.

## Running the automated demo script

```bash
# Full run from the start
./scripts/demo-run.sh

# Restart from a specific step (e.g. after step 9a fails)
START_STEP=9a ./scripts/demo-run.sh
```

Valid step IDs: `1 2 3 4 5 6 7a 7b 7c 7d 8 9a 9b`

Pre-set variables in `scripts/demo-env.sh` (gitignored):
```bash
export IMAGE="quay.io/waba/bootc-guide:dev"
export VM_SSH="demo@<vm-ip>"
export SNO_API="https://api.your-cluster.example.com:6443"
export SNO_TOKEN="$(oc whoami -t 2>/dev/null || true)"
export DISK_IMAGE="quay.io/waba/bootc-guide:prod-disk"  # set to skip disk rebuild
```
