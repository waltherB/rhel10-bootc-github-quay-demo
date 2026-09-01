# Documentation Index

Complete index of all documentation for the RHEL 10 bootc OpenShift Virtualization deployment.

---

## 🚀 Start Here

### For Quick Deployment
👉 **[DEPLOYMENT-QUICK-START.md](DEPLOYMENT-QUICK-START.md)** (3.8 KB, 2-min read)
- One-liner deployment command
- Step-by-step checklist
- Common troubleshooting commands
- Monitoring dashboard

### For Complete Walkthrough
👉 **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** (12 KB, comprehensive)
- Full prerequisites & setup
- Detailed deployment flow
- Component explanations
- Troubleshooting section with solutions
- CI/CD integration patterns
- VM lifecycle operations

### For Verification
👉 **[TAG-AUDIT.md](TAG-AUDIT.md)** (8 KB, technical audit)
- Image tag consistency verification
- Ansible playbook audit (✅ all correct)
- GitHub Actions workflow audit (✅ all correct)
- Tag mapping & naming conventions
- Deployment workflow diagrams

### For Overview
👉 **[DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md)** (8 KB, summary)
- What was created
- Audit results (all files reviewed)
- How it all works together
- Integration points
- Next steps for your team

---

## 📝 Presentation & Demo

### Danish Speaker Notes (for slides)
**[speaker-notes-da.md](speaker-notes-da.md)**
- Structured as PowerPoint slides
- 4 main presentation slides
- Audience-tailored messaging
- Key talking points per slide
- Strong opening & closing

### OpenShift Virtualization Technical Guide
**[openShift-virtualization-extension.md](openShift-virtualization-extension.md)**
- Deep technical dive
- Architecture details
- OpenShift Virt specifics
- KubeVirt integration
- CDI (Containerized Data Importer) explanation

### Demo Checklist
**[live-demo-checklist.md](live-demo-checklist.md)**
- Pre-demo verification steps
- Demo script walkthrough
- Timing guidance
- Rollback procedure
- Troubleshooting during live demo

---

## 📚 Project Documentation

### Project Overview
**[README.md](../README.md)** (Root level)
- Project purpose & architecture
- Presentation resume
- Technical overview
- Setup & kørsel guidance
- OpenShift Virtualization integration

### Quadlet Chatbot Demo
**[quadlet-chatbot-demo.md](quadlet-chatbot-demo.md)**
- Quadlet systemd demo
- ChatGPT integration example

---

## 🛠️ Deployment Tools

### Deployment Script
**[scripts/deploy-to-openshift-virt.sh](../scripts/deploy-to-openshift-virt.sh)** (267 lines)
- Executable bash script
- Orchestrates full deployment
- Pre-flight checks
- Image verification
- Ansible playbook integration
- Post-deployment info display

### Ansible Playbooks
**[ansible/provision-vm.yml](../ansible/provision-vm.yml)**
- Creates Kubernetes resources
- Sets up CDI for disk import
- Provisions KubeVirt VM
- Cloud-init configuration
- RBAC & security setup

**[ansible/upgrade-vm.yml](../ansible/upgrade-vm.yml)**
- Checks bootc status
- Stages new OS image
- Reboots into new version
- Full update workflow

### Scripts Directory
**[scripts/](../scripts/)**
- `deploy-to-openshift-virt.sh` - NEW! Main deployment orchestrator
- `local-build.sh` - Local ARM64 build (MacBook M4)
- `local-push.sh` - Push to Quay
- `local-sign-keyless.sh` - Sign with Cosign
- `local-build-qcow2.sh` - Convert to QCOW2 disk
- `local-promote-disk.sh` - Promote disk image
- `demo-run.sh` - Automated full demo
- And more...

---

## 📋 Document Quick Reference

| Document | Type | Size | Purpose |
|----------|------|------|---------|
| DEPLOYMENT-QUICK-START.md | Guide | 3.8 KB | One-liner, checklist, commands |
| DEPLOYMENT-GUIDE.md | Reference | 12 KB | Complete walkthrough |
| TAG-AUDIT.md | Audit | 8 KB | Image tag verification |
| DEPLOYMENT-SUMMARY.md | Summary | 8 KB | Overview & integration |
| speaker-notes-da.md | Slides | ~ | Presentation guide (Danish) |
| openShift-virtualization-extension.md | Technical | ~ | Deep dive |
| live-demo-checklist.md | Checklist | ~ | Demo day guide |
| README.md | Overview | ~ | Project introduction |

---

## 🎯 By Use Case

### "I want to deploy now"
1. Read: [DEPLOYMENT-QUICK-START.md](DEPLOYMENT-QUICK-START.md)
2. Run: `./scripts/deploy-to-openshift-virt.sh`
3. Monitor: `watch -n 5 'oc get dv -n bootc-vms && oc get vmi -n bootc-vms'`
4. Connect: `ssh demo@<IP>`

### "I need to understand the full process"
1. Start: [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)
2. Verify: [TAG-AUDIT.md](TAG-AUDIT.md)
3. Deep dive: [openShift-virtualization-extension.md](openShift-virtualization-extension.md)
4. Demo: [live-demo-checklist.md](live-demo-checklist.md)

### "I need to give a presentation"
1. Use: [speaker-notes-da.md](speaker-notes-da.md)
2. Reference: [README.md](../README.md)
3. Demo: [live-demo-checklist.md](live-demo-checklist.md)
4. Deep questions: [openShift-virtualization-extension.md](openShift-virtualization-extension.md)

### "I need to troubleshoot"
1. Quick: [DEPLOYMENT-QUICK-START.md](DEPLOYMENT-QUICK-START.md#-troubleshooting-quick-links)
2. Detailed: [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md#-monitoring--troubleshooting)
3. Verification: [TAG-AUDIT.md](TAG-AUDIT.md)

### "I need to verify image tags"
1. Read: [TAG-AUDIT.md](TAG-AUDIT.md)
2. Review: [DEPLOYMENT-SUMMARY.md](DEPLOYMENT-SUMMARY.md#-image-tag-coverage)
3. Check: [README.md](../README.md#tagging-strategy)

---

## 🔗 Cross-References

### Image Build & Promotion
- GitHub Actions: `.github/workflows/build-sign-push.yml` (builds :dev-* tags)
- GitHub Actions: `.github/workflows/build-qcow2.yml` (builds containerDisk)
- GitHub Actions: `.github/workflows/promote-rhel10-bootc-prod` (promotes to :prod-*)
- Script: `scripts/local-promote-disk.sh` (manual promotion option)

### Local Development
- Script: `scripts/local-build.sh` (ARM64 build on MacBook)
- Script: `scripts/local-build-qcow2.sh` (Convert to QCOW2)
- Script: `scripts/demo-run.sh` (Full automated demo)

### OpenShift Virtualization
- Ansible: `ansible/provision-vm.yml` (VM provisioning)
- Ansible: `ansible/upgrade-vm.yml` (OS updates)
- Script: `scripts/deploy-to-openshift-virt.sh` (Deployment orchestrator)

---

## ✅ Quality Assurance

All documentation has been:
- ✅ Reviewed for consistency
- ✅ Tested for accuracy
- ✅ Verified for completeness
- ✅ Audit: All image tags are correct
- ✅ Audit: All Ansible playbooks are correct
- ✅ Audit: All GitHub Actions workflows are correct

---

## 🎓 Key Learning Points

### About Image-Based OS Lifecycle
- OS is now a versioned artifact (like Docker images)
- Build once, deploy many times
- Full rollback capability
- Traceability from git commit → image digest → running system

### About This Demo
- Two separate architecture paths (ARM64 for MacBook, AMD64 for CI/cloud)
- No cross-arch emulation (eliminates complex bugs)
- Digest preservation across dev → prod promotion
- GitOps approach (everything in code)

### About OpenShift Virtualization
- Uses KubeVirt under the hood
- CDI for containerized disk import
- Declarative VM provisioning
- Cloud-init for initial setup
- UEFI/EFI required (bootc images are GPT-only)

---

## 📞 Support & Questions

- **Quick Commands?** → [DEPLOYMENT-QUICK-START.md](DEPLOYMENT-QUICK-START.md)
- **Troubleshooting?** → [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md#-monitoring--troubleshooting)
- **Tags & Verification?** → [TAG-AUDIT.md](TAG-AUDIT.md)
- **Architecture Questions?** → [openShift-virtualization-extension.md](openShift-virtualization-extension.md)
- **Live Demo Questions?** → [live-demo-checklist.md](live-demo-checklist.md)

---

**Last Updated:** 2026-09-01  
**Status:** ✅ Production Ready  
**All Documentation:** Complete & Verified
