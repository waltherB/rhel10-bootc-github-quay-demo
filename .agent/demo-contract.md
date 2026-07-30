# Demo Contract

## Demo Purpose

The demo is not primarily about traditional Linux administration.

The demo is about showing how the operating system lifecycle can move into a container-native, Git-driven, automated workflow.

## Primary Message

```text
RHEL Image Mode and bootc let us manage operating systems as versioned, reproducible image artifacts.
```

## What The Audience Must Understand

By the end of the demo, the audience should understand:

1. The OS is defined in source control.
2. The OS image is built through a repeatable pipeline.
3. The image is distributed through a container registry.
4. Systems can update transactionally from image versions.
5. Rollback is part of the lifecycle model.
6. The model aligns with platform engineering and GitOps thinking.

## What To Emphasize

- Git as source of truth
- Containerfile as OS definition
- Quay as distribution point
- CI/CD as control plane
- bootc as lifecycle mechanism
- Rollback as operational safety
- Versioning and traceability

## What Not To Over-Emphasize

Avoid spending too much live-demo time on:

- Basic package installation
- Manual Linux administration
- Long builds
- Debugging registry login issues
- Deep systemd internals
- Non-essential local laptop details

## Desired Story Arc

```text
Problem:
Traditional server lifecycle creates drift, manual patching and inconsistent states.

Solution:
Define the OS as an image and manage it through Git, CI/CD and registry workflows.

Proof:
Build, publish, boot, update and roll back a RHEL bootc image.

Enterprise Value:
Standardization, auditability, faster recovery and better platform control.
```

## Demo Success Criteria

A successful demo shows:

- A clear source change
- A successful image build
- A pushed registry image
- A booted VM or target system
- A visible version marker
- An update path
- A rollback or recovery explanation

## Minimum Viable Live Demo

If time is short or network is unreliable, demonstrate:

1. Repository structure
2. Containerfile change
3. Pre-built image in Quay
4. Pre-built VM booted from QCOW2
5. bootc status
6. Update/rollback explanation using prepared outputs

## Full Live Demo

If conditions are good, demonstrate:

1. Validate prerequisites
2. Build image locally
3. Test image locally
4. Push to Quay
5. Generate QCOW2
6. Boot VM
7. Show version marker
8. Change image
9. Build and push new tag
10. bootc upgrade/switch
11. Rollback
