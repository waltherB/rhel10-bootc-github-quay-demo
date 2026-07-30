# Bootc Demo Architecture

## Architecture Goal

The architecture demonstrates an operating-system supply chain using familiar cloud-native patterns:

```text
Source Control -> Build -> Registry -> Deploy -> Update -> Rollback
```

## Logical Components

### GitHub Repository

Role:

- Source of truth for OS definition.
- Stores Containerfile, scripts, workflow definitions and demo documentation.

Value:

- Change history
- Reviewable changes
- Audit trail
- Repeatability

### Containerfile

Role:

- Defines the image-based operating system.
- Adds packages, configuration, files and systemd enablement.

Design principles:

- Keep image changes declarative.
- Keep secrets out of layers.
- Keep debug/demo markers visible.
- Keep the build deterministic where possible.

### Local Build Engine

Role:

- Builds the image locally with Podman or Buildah.
- Enables fast iteration during demo preparation.

Consideration:

- On Mac M-series, ensure the target platform is ARM64 when testing in UTM on ARM.

### GitHub Actions

Role:

- Automates build validation and publishing.
- Provides CI/CD story.

Recommended stages:

```text
checkout
login to registry.redhat.io
login to quay.io
build image
inspect image
push image
sign image
create SBOM
publish summary
```

### Quay.io

Role:

- Stores and distributes bootc images.
- Provides registry-based lifecycle anchor.

Recommended design:

- Use immutable commit tags.
- Use promotion tags for demo: candidate and stable.
- Avoid relying only on latest.

### bootc-image-builder

Role:

- Converts a bootc container image into bootable artifacts such as QCOW2 for VM testing.

Demo value:

- Makes the image concrete by booting it as a VM.
- Bridges container-native OS definition into virtualization workflows.

### Target VM

Role:

- Demonstrates the final system state.
- Shows bootc status, version marker, services and update behavior.

Validation commands:

```bash
cat /etc/os-release
sudo bootc status
cat /etc/demo-release || true
systemctl status <demo-service> || true
```

## Architecture Diagram

```text
+------------------+        +-------------------+        +------------------+
| Developer Laptop |        | GitHub Repository |        | GitHub Actions   |
| Podman / UTM     | -----> | Containerfile     | -----> | Build / Validate |
+------------------+        +-------------------+        +------------------+
          |                                                        |
          | local build/test                                       | push
          v                                                        v
+------------------+        +-------------------+        +------------------+
| Local Image      | -----> | Quay.io Registry  | -----> | bootc Target VM  |
| ARM64/AMD64      |        | versioned tags    |        | update/rollback  |
+------------------+        +-------------------+        +------------------+
```

## Recommended Enterprise Architecture Enhancements

### Image Promotion

```text
dev -> candidate -> stable
```

### Signing

Use cosign for signing image artifacts.

### SBOM

Generate SBOM during CI to support supply-chain visibility.

### Vulnerability Scanning

Use Quay scanning where available and include vulnerability status in demo narrative.

### GitOps Alignment

Use Git as source of truth for OS image definition. If using OpenShift, use GitOps for the app/platform layer and avoid overselling Argo CD as direct host lifecycle management unless supported by a separate orchestration pattern.

### OpenShift Virtualization Alignment

Extend the demo by importing the QCOW2 or registry-backed image into OpenShift Virtualization as a VM lifecycle demonstration.

## Design Trade-Offs

### Local Build vs CI Build

Local build:

- Faster for demos.
- Better for Mac ARM testing.
- Less enterprise governance.

CI build:

- Better auditability.
- Better repeatability.
- Requires runner architecture planning.

### `latest` Tag vs Immutable Tags

`latest`:

- Easy for demo.
- Bad for traceability.

Commit tags:

- Better auditability.
- Better rollback mapping.

Recommended:

Use both:

```text
latest
commit-<sha>
stable
```

### Live Build vs Pre-Built Image

Live build:

- Strong visual proof.
- Risky due to time and network.

Pre-built image:

- Reliable.
- Less dramatic.

Recommended:

Start a live build early, but have pre-built image ready.
