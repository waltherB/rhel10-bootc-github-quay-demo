# Speaker Notes - RHEL Image Mode / bootc Demo

## Opening

Today I want to show a different way of thinking about Linux lifecycle management.

Instead of installing a server and then continuously modifying it over time, we define the operating system as an image. That image is built from source, stored in a registry and used as the lifecycle artifact for the system.

The important concept is not just bootc as a command. The important concept is the operating model around it.

## Key Message

```text
The operating system becomes a versioned, reproducible and rollback-capable artifact.
```

## Why This Matters

Traditional server management often creates:

- Configuration drift
- Manual patching windows
- Inconsistent environments
- Weak rollback options
- Poor traceability from change request to running system

Image Mode helps shift this toward:

- Git-based change control
- Repeatable builds
- Registry-based distribution
- Transactional updates
- Operational rollback
- Better standardization

## Why Immutable Images and Containers Matter

An immutable image is a defined version of the operating system. We do not treat
the running host as a place to make uncontrolled, permanent changes. When the
system needs to change, we build and deploy a new image version instead.

Containers use the same model: the image is built once, promoted through the
pipeline and run consistently in each environment. The container or VM can be
replaced, but the image remains the traceable source of its state.

This matters because it gives us:

- **Consistency:** development, test and production use the same built artifact.
- **Reduced drift:** changes are made in source and rebuilt, rather than applied
	differently to individual machines.
- **Safer operations:** updates can be tested and staged before reboot or rollout.
- **Fast recovery:** a failed update can return to a known-good image.
- **Traceability:** we can connect the running system to a specific image digest,
	source change and build pipeline.

Immutability does not mean the system can never change. It means changes are
intentional, versioned and delivered through a controlled lifecycle.

## Demo Step: Repository

What I say:

This repository is the source of truth. The Containerfile defines the OS state, scripts automate local operations, GitHub Actions can build the image, and Quay acts as the distribution point.

Why it matters:

This makes OS changes reviewable and auditable before they become running infrastructure.

## Demo Step: Containerfile

What I say:

The Containerfile is where we define the intended operating system state. This can include packages, files, services and configuration.

This is the important difference from manually configuring a server: the
Containerfile describes the desired image, while the running system is treated
as a deployed version of that image.

Customer value:

This enables standard operating system baselines, golden images and consistent deployment patterns.

## Demo Step: Build

What I say:

Now we build the operating system image. This is similar to how application teams build container images, but the target is a bootable OS.

Customer value:

The same governance patterns used for applications can now be applied to the OS layer.

The image is the immutable handoff between build and runtime. Once it is built
and tested, the same artifact can be promoted instead of rebuilding or manually
recreating the system in each environment.

## Demo Step: Quay

What I say:

The image is published to Quay. This means that the OS lifecycle is now tied to a registry artifact with tags, history and optionally scanning/signing.

Customer value:

The registry becomes a controlled distribution point for standardized OS images.

## Demo Step: QCOW2 / VM

What I say:

To make the result tangible, we convert the bootc image into a VM disk and boot it.

Customer value:

This bridges modern image-based lifecycle management with existing virtualization environments.

## Demo Step: bootc status

What I say:

The running system knows which image it is based on. That gives us a clear link between source, image and running host.

Customer value:

This improves traceability and supportability.

## Demo Step: Update

What I say:

Instead of patching individual packages manually, we move the system to a new image version.

Customer value:

This makes change handling more predictable and easier to test before production.

We are replacing the system with a new declared version, not accumulating an
unknown set of package changes on the existing host. That is how immutability
reduces drift over time.

## Demo Step: Rollback

What I say:

If the new state is not good, we roll back to the previous known-good image.

Customer value:

Rollback becomes operationally simple and part of the lifecycle design.

Because the previous image remains a known-good version, recovery does not
depend on remembering which individual packages or configuration files changed.

## Audience-Specific Angles

### Linux Operations

Focus on:

- Standard baselines
- Patch consistency
- Reduced drift
- Faster recovery

### OpenShift / Kubernetes Teams

Focus on:

- GitOps mental model
- Immutable infrastructure
- Platform engineering
- OpenShift Virtualization extension

### Enterprise Architects

Focus on:

- Governance
- Traceability
- Supply chain
- Lifecycle model

### Management

Focus on:

- Lower operational risk
- More predictable changes
- Faster rollback
- Clear ownership model

## Strong Closing

This demo is not about replacing every Linux management process tomorrow. It is about showing where Linux lifecycle management is moving: toward versioned images, controlled pipelines, registry distribution and safer Day 2 operations.

For many customers, the first step is not production rollout. The first step is an assessment: where would image-based lifecycle management reduce drift, improve compliance or simplify platform operations?
