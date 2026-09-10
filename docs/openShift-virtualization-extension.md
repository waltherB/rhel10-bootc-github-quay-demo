# OpenShift Virtualization Extension

## Purpose

This optional extension shows how the bootc demo can connect to OpenShift Virtualization and platform engineering conversations.

## Message

```text
RHEL Image Mode can help standardize VM operating system lifecycle while OpenShift Virtualization provides the platform to run and manage VMs alongside containers.
```

## Demo Extension Options

### Option 1 - Import QCOW2 As VM Disk

Flow:

```text
bootc image
  -> QCOW2
  -> upload/import to OpenShift Virtualization
  -> boot VM
```

Value:

- Shows migration path for VM-centric customers.
- Connects RHEL lifecycle management with OpenShift Virtualization.

### Option 2 - Use DataVolume Import

Flow:

```text
QCOW2 hosted/imported
  -> DataVolume
  -> VirtualMachine
```

Value:

- More Kubernetes-native.
- Better for GitOps demonstration.

### Option 3 - GitOps VM Definition

Flow:

```text
Git repo
  -> Argo CD
  -> VM manifests
  -> OpenShift Virtualization
```

Important:

Argo CD manages Kubernetes resources. It does not directly manage a non-Kubernetes host OS by itself. For host updates, use bootc lifecycle mechanisms or an orchestration layer.

## Enterprise Story

This extension is valuable for customers considering VMware alternatives or OpenShift Virtualization adoption.

Positioning:

- VM platform modernization
- Standardized RHEL images
- GitOps-controlled VM definitions
- Image-based lifecycle management
- Reduced configuration drift

## Recommended Atea Service Link

Service:

```text
OpenShift Virtualization + RHEL Image Mode Assessment
```

Deliverables:

- Current VM OS lifecycle assessment
- Candidate workload selection
- Golden image design
- OpenShift Virtualization import pattern
- Day 2 update and rollback design
- Pilot plan
