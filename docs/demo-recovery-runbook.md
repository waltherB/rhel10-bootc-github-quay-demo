# Live Demo Recovery Runbook

## Principle

The goal during a live demo is not to prove that every dependency is perfect. The goal is to preserve the story and show the architecture.

## Recovery Decision Tree

```text
Command failed
  |
  +-- Is it critical to the story?
       |
       +-- No  -> skip and explain
       |
       +-- Yes -> is there a backup artifact?
                |
                +-- Yes -> use backup
                |
                +-- No  -> switch to architecture/screenshot explanation
```

## S1: Registry Unavailable

### Fast Recovery

Use pre-pulled local image:

```bash
podman images | grep bootc
```

If available, continue from local image or pre-generated QCOW2.

### What To Tell Audience

```text
The registry is normally the distribution point. For the demo, I will use a pre-built image so we can focus on the lifecycle model rather than network availability.
```

## S1: VM Will Not Boot

### Fast Recovery

Use backup VM snapshot.

### If no backup VM

Show captured output:

```text
sudo bootc status
cat /etc/demo-release
```

### What To Tell Audience

```text
The VM boot is just the visible runtime target. The important part is that the system is derived from a versioned image artifact.
```

## S1: Image Build Fails

### Fast Recovery

Pull known-good image:

```bash
podman pull "$QUAY_IMAGE:stable"
```

or:

```bash
podman pull "$QUAY_IMAGE:latest"
```

### What To Tell Audience

```text
A live build depends on network, registry and runner state. In production, this would run in CI/CD with controlled credentials and repeatable runners. I will continue with a known-good build.
```

## S2: Signing Fails

### Fast Recovery

Skip signing and explain it as a supply-chain enhancement.

### What To Tell Audience

```text
Signing is not required to understand the bootc lifecycle, but it is important for production supply-chain control.
```

## S2: SBOM Fails

### Fast Recovery

Show previously generated SBOM or explain planned CI step.

## S3: Warning Output

### Rule

Do not debug warnings live unless they affect the story.

Say:

```text
That warning is not part of the lifecycle path, so I will keep the demo focused.
```

## Required Backup Assets

Before every important demo, prepare:

```text
backup/qcow2/disk.qcow2
backup/screenshots/github-action-success.png
backup/screenshots/quay-image-tags.png
backup/screenshots/bootc-status-v1.png
backup/screenshots/bootc-status-v2.png
backup/command-output/bootc-status-v1.txt
backup/command-output/bootc-status-v2.txt
```

## Recovery Prompts For The Agent

```text
BOOTC_RECOVERY
This command failed: <command>
Error: <error output>
I am live on stage. Give me the fastest recovery path.
```
