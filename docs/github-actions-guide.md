# GitHub Actions Guide

## Purpose

GitHub Actions should demonstrate repeatable OS image builds from source control.

## Recommended Workflow Stages

```text
1. Checkout repository
2. Validate required variables
3. Login to registry.redhat.io
4. Login to quay.io
5. Build image
6. Inspect image
7. Push image
8. Optional sign image
9. Optional generate SBOM
10. Publish summary
```

## Required Secrets

```text
RH_REGISTRY_USERNAME
RH_REGISTRY_PASSWORD
QUAY_USERNAME
QUAY_TOKEN
```

## Required Variables

```text
QUAY_IMAGE=quay.io/<namespace>/<repo>
TARGET_PLATFORM=linux/arm64 or linux/amd64
```

## Architecture Warning

If the demo target is a Mac M-series UTM VM, the image should normally be ARM64. GitHub-hosted Linux runners are commonly x86_64, so ARM64 builds may require local build, emulation or a self-hosted ARM64 runner.

## Recommended Workflow Behavior

- Fail fast if QUAY_IMAGE is missing.
- Fail fast if TARGET_PLATFORM is missing.
- Tag every image with commit SHA.
- Optionally update `latest` only from main.
- Print summary without secrets.

## Example Summary Output

```markdown
# bootc Image Build Summary

Image: quay.io/example/rhel10-bootc-demo
Tag: commit-abc1234
Platform: linux/arm64
Commit: abc1234
Pushed: yes
Signed: yes/no
SBOM: yes/no
```

## Failure Handling

If build fails:

- Show the failing step.
- Show the last relevant log lines.
- Recommend local reproduction command.

If push fails:

- Verify Quay namespace.
- Verify token scope.
- Verify repository exists.

If signing fails:

- Treat as S2 unless signing is the core demo.
- Continue lifecycle demo with unsigned image if acceptable.
