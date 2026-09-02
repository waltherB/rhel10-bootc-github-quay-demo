# RHEL 10 Image Mode Demo – GitHub Actions + Quay + OpenShift Virtualization

# RHEL 10 Image Mode Demo: Overblik og Præsentation

Dette repository demonstrerer en moderne, image-baseret livscyklusstyring for operativsystemer (OS), der erstatter traditionel, manuel serveradministration.

**Målgruppe:** (Tilpas efter publikum: Linux-drift, OpenShift/K8s, Arkitekter, Ledelse)
**Hovedbudskab:** Operativsystemet skal behandles som et versionsstyret, reproducerbart artefakt, der kan rulles tilbage.

---

## 🚀 Præsentationsresume (Hvad vi viser)

Denne demo følger en klar, lineær fortælling, der kan bruges direkte i en PowerPoint-præsentation:

1.  **Problemet (Slide 1):** Traditionel drift fører til konfigurationsdrift, uensartethed og dårlig sporbarhed.
2.  **Løsningen (Slide 2):** Vi introducerer *Immutable Images* – OS'et som et versionsstyret artefakt.
3.  **Arkitekturen (Slide 3):** Vi gennemgår de 5 nøglekomponenter:
    *   **Kildekode:** Sandhedskilden (Repository).
    *   **Definition:** Deklarerer tilstanden (Containerfile).
    *   **Bygning:** Skaber det immutable artefakt (Build).
    *   **Distribution:** Centralt, versionsstyret lager (Quay Registry).
    *   **Runtime:** Kører artefaktet (QCOW2 / VM).
4.  **Live Demo (Slide 4):** Vi gennemgår hele flowet:
    *   **Build:** Kører `local-build.sh` for at skabe et ARM64 image.
    *   **Push & Sign:** Pusher og signerer artefaktet til Quay.
    *   **VM Provisioning:** Starter en VM fra det nye image.
    *   **Opdatering & Rollback:** Simulerer en opdatering til en ny version og demonstrerer en øjeblikkelig, kontrolleret rollback til den forrige, kendte tilstand.

---

## ⚙️ Teknisk Overblik (For dybdegående sektioner)

### 1. Arkitektur og Platformer
Demoen understøtter to fuldstændigt separate, native stier for at undgå emulering:
*   **ARM64 (Local):** Kører på MacBook Pro M4 via `local-build.sh` og UTM.
*   **AMD64 (CI):** Kører på GitHub-hosted runners og OpenShift Virtualization (x86_64).

### 2. Nøgleworkflows
*   **Local Flow (ARM64):** `local-build.sh` $\rightarrow$ `local-push.sh` $\rightarrow$ `local-sign-keyless.sh` $\rightarrow$ `local-build-qcow2.sh`.
*   **CI Flow (AMD64):** `build-sign-push.yml` builds and pushes both the bootc image and VM disk.
*   **Promotion:** `promote-rhel10-bootc-prod` sikrer, at `:prod` altid har samme digest som `:dev`.

### 3. OpenShift Virtualization (KubeVirt)
Vi udvider demoen til at vise, hvordan CDI importerer VM-disken (`.qcow2`) fra Quay ved hjælp af et specialiseret `FROM scratch` OCI image. Dette er den mest avancerede del og viser integrationen med et enterprise-platform.

## 🛠️ Opsætning og Kørsel

**For at køre demoen:**
1.  Klon repository'et.
2.  Følg `scripts/demo-env.sh.example` for at sætte miljøvariabler.
3.  Kør `scripts/demo-run.sh` for en komplet, automatiseret gennemgang.

**Vigtigt:**
*   **Secrets:** Sørg for at opsætte GitHub Secrets (`QUAY_USERNAME`, `QUAY_TOKEN`, etc.) og GitHub Variables (`QUAY_IMAGE`).
*   **Præstation:** For at sikre, at demoen kører fejlfrit, skal man være opmærksom på, at ARM64 og AMD64 stierne er *native* og aldrig krydskompileres.

## 📚 Yderligere Dokumentation
*   [Speaker Notes (DA)](docs/speaker-notes-da.md): Detaljeret manuskript til præsentationen.
*   [OpenShift Virtualization Guide](docs/openShift-virtualization-extension.md): Dybdegående guide til OpenShift-integrationen.
*   [Live Demo Checklist](docs/live-demo-checklist.md): Tjekliste til at sikre, at alle trin er dækket.

For a full step-by-step walkthrough — local build, CI pipeline, VM provisioning, live OS update, and rollback — see the [demo script](docs/demo-script.md).

Target setup:

- MacBook Pro M4
- Podman + Podman Desktop
- UTM for RHEL 10 VMs (ARM64, local)
- Quay.io as image registry
- GitHub as source repo and CI
- OpenShift Virtualization (KubeVirt) for VM lifecycle on an x86_64 SNO cluster
- Ansible for VM provisioning and upgrades

> Important: replace `quay.io/waba/bootc-guide` with your actual Quay namespace/repository throughout.

### Architecture split: ARM64 (local) vs AMD64 (CI)

The demo deliberately never cross-builds or emulates a foreign architecture — that's what caused a
persistent "image not known / no such container" error against `bootc-image-builder` in earlier
iterations of this project. Instead there are two fully separate, native-only paths that never cross:

| | ARM64 | AMD64 |
|---|---|---|
| **Built on** | MacBook Pro M4, natively (`podman build`, no `--platform` emulation) | GitHub-hosted `ubuntu-latest` runner, natively |
| **Image tag** | `:dev-arm64` / `:prod-arm64` | `:dev-amd64` / `:prod-amd64` |
| **Disk tag** | `:dev-disk-arm64` / `:prod-disk-arm64` | `:dev-disk-amd64` / `:prod-disk-amd64` |
| **Used for** | Local UTM VM demo | OpenShift Virtualization on the x86_64 SNO cluster |
| **Built by** | `local-build.sh`, `local-build-qcow2.sh` | `.github/workflows/build-sign-push.yml` |

## Quick local flow (ARM64, for the UTM VM)

```bash
podman login registry.redhat.io
podman login quay.io
cosign login quay.io -u <your-quay-username> -p <your-quay-token>

export IMAGE_ARM=quay.io/waba/bootc-guide:dev-arm64

./scripts/local-build.sh          # build OCI bootc image, native arm64
./scripts/local-test.sh           # smoke test as container
./scripts/local-push.sh           # push :dev-arm64 to Quay
./scripts/local-sign-keyless.sh   # sign with keyless Cosign
./scripts/local-build-qcow2.sh    # convert to qcow2 natively (arm64), push containerDisk to Quay
```

> **Note:** `cosign` uses its own credential store — run `cosign login` separately from `podman login`.  
> Podman auth is stored in `~/.config/containers/auth.json` on macOS.  
> `bootc-image-builder` requires a **rootful** Podman Machine on macOS (`podman machine set --rootful`) — `local-build-qcow2.sh` checks this and fails fast with the fix if it's rootless.

Import `output/qcow2/disk-arm.qcow2` in UTM to create a local ARM VM.

## Tagging strategy

| Tag | Produced by | Content |
|---|---|---|
| `:dev-arm64` | `local-build.sh` + `local-push.sh` | Local ARM64 bootc image, for UTM |
| `:dev-disk-arm64` | `local-build-qcow2.sh` | ARM64 KubeVirt containerDisk, for UTM only |
| `:dev-amd64` | `build-sign-push.yml`, every push to `main` | AMD64 bootc image, native GitHub-hosted build |
| `:dev-disk-amd64` | `build-sign-push.yml` | AMD64 KubeVirt containerDisk, for CDI import on SNO |
| `:prod-amd64` | `promote-rhel10-bootc-prod` workflow | Promoted from `:dev-amd64` (same digest) |
| `:prod-disk-amd64` | `local-promote-disk.sh` | Promoted from `:dev-disk-amd64` (same digest, via `skopeo copy`) |
| `:v1.0.0` | `git tag v1.0.0` | Immutable release |

SHA traceability is preserved via the image digest — no `dev-<sha>` tags needed.

## GitHub Actions

Three workflows drive CI:

- **`build-sign-push.yml`** — on every push to `main` or manual dispatch. Builds the AMD64 image and qcow2 containerDisk natively on a GitHub-hosted `ubuntu-latest` runner, then pushes `:dev-amd64` and `:dev-disk-amd64` to Quay. It also builds the ARM64 image on a self-hosted ARM64 runner and pushes `:dev-arm64`. The jobs are fully independent and never emulate AMD64 on the Mac.
- **`promote-rhel10-bootc-prod`** (manual `workflow_dispatch`, self-hosted runner) — promotes a given source tag to `:prod` via `skopeo copy` (same digest, no rebuild), then signs it with keyless Cosign.

Create these GitHub repository secrets:

- `RH_REGISTRY_USERNAME`
- `RH_REGISTRY_PASSWORD`
- `QUAY_USERNAME`
- `QUAY_TOKEN`
- `RHSM_ORG`
- `RHSM_ACTIVATION_KEY`

Create this GitHub repository variable (used by `promote-prod.yml`):

- `QUAY_IMAGE=quay.io/waba/bootc-guide`

The `build-arm64` job in `build-sign-push.yml` needs a self-hosted ARM64 runner (label `[self-hosted, ARM64]`) — adjust the label if yours differs. `promote-prod.yml` also expects a self-hosted runner.

## OpenShift Virtualization

The `ansible/` and `gitops/openshift-virt/` directories extend the demo to a Single Node OpenShift cluster with OpenShift Virtualization. This path always uses the **AMD64** image/disk — the x86_64 SNO cluster can't run arm64.

CDI (Containerized Data Importer) imports the VM disk from Quay using a **KubeVirt containerDisk** image — a `FROM scratch` OCI image with the qcow2 at `/disk/disk.qcow2`. This avoids the imagemode OCI format limitation in CDI's registry importer.

```bash
# Install dependencies
pip install ansible kubernetes
ansible-galaxy collection install -r ansible/requirements.yml

# Build the AMD64 bootc image and containerDisk on GitHub's native AMD64 runner
gh workflow run build-sign-push.yml --ref main

# Promote :dev-disk-amd64 -> :prod-disk-amd64 (same digest, skopeo copy)
SOURCE_DISK=quay.io/waba/bootc-guide:dev-disk-amd64 \
TARGET_DISK=quay.io/waba/bootc-guide:prod-disk-amd64 \
  ./scripts/local-promote-disk.sh

# Provision VM on SNO
ansible-playbook ansible/provision-vm.yml \
  -e disk_image=quay.io/waba/bootc-guide:prod-disk-amd64 \
  -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub)\""

# Upgrade VM after a new :prod-amd64 image is promoted
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

Valid step IDs: `1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b`

Step 4 pushes the ARM64 image/signs it, while `build-sign-push.yml` builds the AMD64 image and containerDisk on GitHub Actions. Step 9a assumes that the workflow has completed.

Copy `scripts/demo-env.sh.example` to `scripts/demo-env.sh` (gitignored) and fill in your values — it pre-sets the full ARM64/AMD64 variable set (`IMAGE_ARM`, `IMAGE_AMD`, `DISK_IMAGE_ARM`, `DISK_IMAGE_AMD`, their `PROD_*` counterparts, `VM_SSH`, `SNO_API`, `SNO_TOKEN`, etc.) and is sourced automatically by `demo-run.sh`.
