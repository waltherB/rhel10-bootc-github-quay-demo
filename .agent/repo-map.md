# Repository Map

This file describes the expected structure and intent of the bootc demo repository. The agent must inspect the actual repository before making repo-specific claims.

## Expected Top-Level Files

```text
Containerfile
README.md
.github/workflows/
scripts/
docs/
config/
files/
.agent/
```

## Containerfile

Purpose:

- Defines the RHEL bootc image.
- Adds OS-level customizations.
- Adds packages, files and systemd configuration.
- Should avoid embedding secrets.

Review focus:

- Base image correctness
- Package installation strategy
- Layer hygiene
- systemd enablement
- File placement
- Registry credential handling
- Architecture assumptions

## .github/workflows

Purpose:

- Automate image build.
- Optionally push to Quay.
- Optionally sign image.
- Optionally generate SBOM.

Review focus:

- Secrets usage
- QUAY_IMAGE variable
- TARGET_PLATFORM variable
- Runner architecture
- Build tool selection
- Login sequence
- Tagging strategy
- Failure visibility

## scripts

Purpose:

Local workflow helpers.

Recommended script model:

```text
00-check-prereqs.sh
01-login-registries.sh
02-build-local.sh
03-test-container.sh
04-push-quay.sh
05-sign-image.sh
06-build-qcow2.sh
07-test-vm.sh
08-bootc-upgrade-demo.sh
09-rollback-demo.sh
99-cleanup.sh
```

Scripts should:

- Use `set -euo pipefail`
- Validate required vars
- Quote variables
- Mask secrets
- Print clear next steps
- Be safe to run during a live demo

## docs

Purpose:

Human-readable demo and operational material.

Recommended files:

```text
demo-script.md
architecture.md
troubleshooting.md
live-demo-checklist.md
speaker-notes.md
repository-overview.md
```

## config

Purpose:

Configuration files for image generation, user creation, image-builder or VM setup.

Review focus:

- No plaintext passwords
- No static secrets
- Clear placeholders
- Architecture notes

## files

Purpose:

Static content copied into the image.

Review focus:

- Correct file paths
- Clear demo marker files
- Minimal payload
- No credentials

## End-to-End Demo Flow

```text
1. Developer changes Containerfile or static files
2. Git commit records desired OS state
3. Local build or GitHub Actions builds image
4. Image is tagged and pushed to Quay
5. Image can be signed and scanned
6. QCOW2 image is generated for VM test
7. VM boots into image-defined OS state
8. A new image version is produced
9. Target system applies bootc update
10. Rollback demonstrates operational safety
```
