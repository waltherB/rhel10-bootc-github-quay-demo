# Quick Deployment Reference

Quick start guide for deploying RHEL 10 bootc to OpenShift Virtualization.

---

## 🚀 One-Liner Deployment

```bash
./scripts/deploy-to-openshift-virt.sh
```

---

## 📋 Step-by-Step Checklist

### Pre-Flight (Do This Once)

- [ ] **Install dependencies:**
  ```bash
  pip install ansible kubernetes
  ansible-galaxy collection install -r ansible/requirements.yml
  ```

- [ ] **Authenticate to OpenShift:**
  ```bash
  oc login https://api.your-cluster.example.com --token=<token>
  ```

- [ ] **Authenticate to Quay:**
  ```bash
  podman login quay.io
  ```

- [ ] **Copy and configure demo environment:**
  ```bash
  cp scripts/demo-env.sh.example scripts/demo-env.sh
  # Edit scripts/demo-env.sh with your values
  ```

### Deployment

- [ ] **Run deployment script:**
  ```bash
  ./scripts/deploy-to-openshift-virt.sh
  ```

- [ ] **Monitor progress (in separate terminal):**
  ```bash
  watch -n 5 'oc get dv -n bootc-vms && echo "---" && oc get vmi -n bootc-vms'
  ```

- [ ] **Wait for VM to be Running (~5-10 minutes)**

- [ ] **Get VM IP address:**
  ```bash
  oc get vmi -n bootc-vms -o wide
  ```

- [ ] **SSH into VM:**
  ```bash
  ssh demo@<IP>
  ```

- [ ] **Inside VM: Verify bootc status:**
  ```bash
  sudo bootc status
  ```

---

## 🎮 Common Commands

### View VM Status
```bash
oc get vmi -n bootc-vms -w
```

### View DataVolume Import Progress
```bash
oc get dv -n bootc-vms -o wide -w
```

### Check CDI Importer Logs
```bash
oc logs -n bootc-vms -l app.kubernetes.io/component=importer -f
```

### Access VM Console
```bash
virtctl console rhel10-bootc-demo -n bootc-vms
```

### Connect to VM via SSH
```bash
ssh demo@<IP>
```

### Inside VM: Check Bootc Status
```bash
sudo bootc status
```

### Inside VM: Check Available Updates
```bash
sudo bootc upgrade --check
```

### Upgrade VM to New OS Image
```bash
ansible-playbook ansible/upgrade-vm.yml
```

### Delete the VM
```bash
oc delete vm rhel10-bootc-demo -n bootc-vms
oc delete namespace bootc-vms
```

---

## 📊 Monitoring Dashboard

Run this in a dedicated terminal to monitor the entire deployment:

```bash
watch -n 5 'echo "=== NAMESPACE ===" && \
oc get namespace bootc-vms && \
echo "=== DATAVOL ===" && \
oc get dv -n bootc-vms && \
echo "=== VM ===" && \
oc get vm -n bootc-vms && \
echo "=== VMI ===" && \
oc get vmi -n bootc-vms && \
echo "=== PVC ===" && \
oc get pvc -n bootc-vms'
```

---

## 🔧 Customization Flags

Override deployment settings via CLI:

```bash
./scripts/deploy-to-openshift-virt.sh \
  --image-ref quay.io/your-org/bootc:prod-amd64 \
  --disk-ref quay.io/your-org/bootc:prod-disk-amd64 \
  --vm-name my-rhel10-vm \
  --namespace my-vms
```

Or via environment variables (`scripts/demo-env.sh`):
```bash
export IMAGE_AMD="quay.io/your-org/bootc:prod-amd64"
export DISK_IMAGE_AMD="quay.io/your-org/bootc:prod-disk-amd64"
export VM_NAME="my-rhel10-vm"
export VM_NAMESPACE="my-vms"
export VM_CORES="4"
export VM_MEMORY="4Gi"
export VM_DISK_SIZE="100Gi"
export VM_STORAGE_CLASS="lvms-vg1"
```

---

## 🛠️ Troubleshooting Quick Links

| Issue | Check |
|-------|-------|
| Image pull fails | `oc logs -n bootc-vms -l app.kubernetes.io/component=importer` |
| VM won't boot | `oc describe vm rhel10-bootc-demo -n bootc-vms` |
| Cannot SSH | `virtctl console rhel10-bootc-demo -n bootc-vms` |
| Slow import | `oc get dv -n bootc-vms -o yaml \| grep -A 5 status` |

See [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md#-monitoring--troubleshooting) for detailed troubleshooting.

---

## 📚 Full Documentation

- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) — Complete deployment walkthrough
- [TAG-AUDIT.md](TAG-AUDIT.md) — Image tag consistency audit
- [openShift-virtualization-extension.md](openShift-virtualization-extension.md) — Technical deep dive
- [speaker-notes-da.md](speaker-notes-da.md) — Presentation guide
