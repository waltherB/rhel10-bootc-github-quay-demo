# ============================================================
#  RHEL 10 bootc Demo – VHS tape
#  Produces a pre-recorded terminal screencast for on-stage playback.
#
#  Prerequisites:
#    brew install vhs
#
#  Record:
#    vhs docs/demo.tape
#
#  Output: docs/demo.gif  docs/demo.mp4
#
#  NOTE: Commands that require live credentials (podman login,
#  ssh into VM, oc login) are stubbed with echo to keep the
#  recording self-contained. Run the real demo interactively
#  with ./scripts/demo-run.sh.
# ============================================================

Output docs/demo.gif
Output docs/demo.mp4

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 800
Set Theme "Dracula"
Set TypingSpeed 40ms
Set Padding 20

# ── Hidden setup ────────────────────────────────────────────
Hide
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show

# ────────────────────────────────────────────────────────────
# INTRO
# ────────────────────────────────────────────────────────────
Type "echo ''"
Enter
Type@20ms "echo '  ╔══════════════════════════════════════════════════╗'"
Enter
Type@20ms "echo '  ║   RHEL 10 Image Mode Demo                       ║'"
Enter
Type@20ms "echo '  ║   GitHub Actions · Quay · OpenShift Virt         ║'"
Enter
Type@20ms "echo '  ╚══════════════════════════════════════════════════╝'"
Enter
Type "echo ''"
Enter
Sleep 3s

# ────────────────────────────────────────────────────────────
# STEP 1 – Show the repo
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 1: Show the repo  ━━'"
Enter
Sleep 1s

Type "ls -1"
Enter
Sleep 2s

Type "cat Containerfile"
Enter
Sleep 5s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 2 – Local build
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 2: Local build on Mac M4  ━━'"
Enter
Sleep 1s

Type "export IMAGE=quay.io/waba/bootc-guide:dev"
Enter
Type "export TARGET_PLATFORM=linux/arm64"
Enter
Sleep 1s

# Stub – real build requires registry login
Type "echo '[stub] podman login registry.redhat.io'"
Enter
Type "echo '[stub] podman build --platform linux/arm64 -t quay.io/waba/bootc-guide:dev .'"
Enter
Sleep 1s
Type "echo '  --> Successfully tagged quay.io/waba/bootc-guide:dev'"
Enter
Sleep 2s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 3 – Smoke test
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 3: Smoke test the image  ━━'"
Enter
Sleep 1s

Type "echo '[stub] podman run --rm -d -p 8080:80 --name bootc-test quay.io/waba/bootc-guide:dev'"
Enter
Sleep 1s
Type "echo '[stub] curl -fsS http://127.0.0.1:8080 | head'"
Enter
Type "echo '  --> <!DOCTYPE html><html>...'"
Enter
Type "echo '[stub] podman exec bootc-test cat /etc/motd'"
Enter
Type "echo '  --> RHEL 10 Image Mode Demo'"
Enter
Type "echo '  --> Built from GitHub, pushed to Quay, deployed with bootc.'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 4 – Push and sign
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 4: Push and sign  ━━'"
Enter
Sleep 1s

Type "echo '[stub] podman push quay.io/waba/bootc-guide:dev'"
Enter
Sleep 1s
Type "echo '[stub] cosign sign quay.io/waba/bootc-guide:dev'"
Enter
Sleep 1s
Type "echo '  --> Signing with keyless OIDC (GitHub Actions / Sigstore)'"
Enter
Type "echo '  --> tlog entry created with index: 12345678'"
Enter
Sleep 2s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 5 – GitHub Actions CI (narration only)
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 5: GitHub Actions CI  ━━'"
Enter
Sleep 1s
Type "echo '  Every push to main triggers:'"
Enter
Type "echo '    build  →  smoke test  →  push :dev  →  cosign sign  →  cosign verify'"
Enter
Sleep 1s
Type "echo '  Only git tags (v*) create a versioned tag.'"
Enter
Type "echo '  >>> Switch to browser: GitHub Actions <<<'"
Enter
Sleep 4s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 6 – Promote :dev → :prod
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 6: Promote :dev → :prod  ━━'"
Enter
Sleep 1s
Type "echo '[stub] skopeo copy docker://quay.io/waba/bootc-guide:dev docker://quay.io/waba/bootc-guide:prod'"
Enter
Sleep 1s
Type "echo '  --> Same digest, just a new tag. No rebuild.'"
Enter
Sleep 2s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 7 – Make a visible change and push
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 7: Make a visible change  ━━'"
Enter
Sleep 1s

Type "echo \"RHEL 10 Image Mode Demo v2 - updated $(date +%F)\" > files/motd"
Enter
Type "cat files/motd"
Enter
Sleep 2s

Type "git add files/motd"
Enter
Type "git commit -m 'chore: bump motd to v2 for live update demo'"
Enter
Sleep 1s
Type "git push"
Enter
Sleep 1s
Type "echo '  --> CI pipeline triggered. Switch to GitHub Actions to show the build.'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 8 – VM status before update
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 8: VM status before update  ━━'"
Enter
Sleep 1s

Type "echo '[stub] ssh demo@192.168.64.10 vm-status'"
Enter
Sleep 1s
Type "echo ''"
Enter
Type "echo '=== bootc status ==='"
Enter
Type "echo 'Current booted image:'"
Enter
Type "echo '  Image:   quay.io/waba/bootc-guide:prod'"
Enter
Type "echo '  Digest:  sha256:aabbcc1122334455...  (OLD)'"
Enter
Type "echo ''"
Enter
Type "echo '=== /etc/motd ==='"
Enter
Type "echo 'RHEL 10 Image Mode Demo'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 9 – Apply the update on the VM
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 9: Apply the update  ━━'"
Enter
Sleep 1s

Type "echo '[stub] ssh demo@192.168.64.10 vm-upgrade'"
Enter
Sleep 1s
Type "echo '=== Checking for update ==='"
Enter
Type "echo 'Update available: quay.io/waba/bootc-guide:prod sha256:ddee9988...'"
Enter
Sleep 1s
Type "echo '=== Pulling and staging new image ==='"
Enter
Type "echo 'layers already present: 12/20'"
Enter
Type "echo 'Fetching layers: [##########] 100%'"
Enter
Sleep 1s
Type "echo 'Staging complete. Rebooting in 5 seconds...'"
Enter
Sleep 2s
Type "echo '[VM rebooting]'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 10 – Verify after reboot
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 10: Verify after reboot  ━━'"
Enter
Sleep 1s

Type "echo '[stub] ssh demo@192.168.64.10 vm-status'"
Enter
Sleep 1s
Type "echo ''"
Enter
Type "echo '=== bootc status ==='"
Enter
Type "echo 'Current booted image:'"
Enter
Type "echo '  Image:   quay.io/waba/bootc-guide:prod'"
Enter
Type "echo '  Digest:  sha256:ddee9988aabbccdd...  (NEW ✓)'"
Enter
Type "echo ''"
Enter
Type "echo '=== /etc/motd ==='"
Enter
Type "echo \"RHEL 10 Image Mode Demo v2 - updated $(date +%F)  (NEW ✓)\""
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 11 – Rollback
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 11: Rollback  ━━'"
Enter
Sleep 1s

Type "echo '[stub] ssh demo@192.168.64.10 sudo bootc rollback'"
Enter
Sleep 1s
Type "echo '  --> Previous deployment staged. Rebooting...'"
Enter
Sleep 2s
Type "echo '[stub] ssh demo@192.168.64.10 vm-status'"
Enter
Sleep 1s
Type "echo '  Digest:  sha256:aabbcc1122334455...  (restored ✓)'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 12 – Ansible provision on OpenShift Virt
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 12: Ansible – provision VM on OpenShift Virt  ━━'"
Enter
Sleep 1s

Type "echo '[stub] oc login https://api.your-cluster.example.com --token=...'"
Enter
Sleep 1s

Type "ansible-playbook ansible/provision-vm.yml --list-tasks"
Enter
Sleep 3s

Type "echo '[stub] ansible-playbook ansible/provision-vm.yml'"
Enter
Sleep 1s
Type "echo '  TASK: Ensure namespace exists        [ok]'"
Enter
Type "echo '  TASK: Create Quay pull secret        [changed]'"
Enter
Type "echo '  TASK: Create ServiceAccount          [changed]'"
Enter
Type "echo '  TASK: Create RBAC Role               [changed]'"
Enter
Type "echo '  TASK: Bind RBAC Role to VM SA        [changed]'"
Enter
Type "echo '  TASK: Allow CDI importer pull        [changed]'"
Enter
Type "echo '  TASK: Deploy VirtualMachine          [changed]'"
Enter
Type "echo '  TASK: Wait for VM to be ready        [ok]'"
Enter
Type "echo '  TASK: Show VM IP                     192.168.2.50'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# STEP 13 – Ansible upgrade on OpenShift Virt
# ────────────────────────────────────────────────────────────
Type@20ms "echo '━━  STEP 13: Ansible – upgrade VM on OpenShift Virt  ━━'"
Enter
Sleep 1s

Type "echo '[stub] ansible-playbook ansible/upgrade-vm.yml'"
Enter
Sleep 1s
Type "echo '  TASK: Check current bootc status     sha256:aabbcc...'"
Enter
Type "echo '  TASK: Check if upgrade available     Update available'"
Enter
Type "echo '  TASK: Run bootc upgrade              [changed]'"
Enter
Type "echo '  TASK: Reboot VM                      [changed]'"
Enter
Type "echo '  TASK: Wait for VM to come back up    [ok]'"
Enter
Type "echo '  TASK: Verify new bootc status        sha256:ddee99... (NEW ✓)'"
Enter
Sleep 3s

Type "clear"
Enter

# ────────────────────────────────────────────────────────────
# OUTRO
# ────────────────────────────────────────────────────────────
Type "echo ''"
Enter
Type@20ms "echo '  ╔══════════════════════════════════════════════════╗'"
Enter
Type@20ms "echo '  ║   Demo complete!                                 ║'"
Enter
Type@20ms "echo '  ║                                                  ║'"
Type@20ms "echo '  ║   Repo: github.com/waba/rhel10-bootc-demo        ║'"
Enter
Type@20ms "echo '  ╚══════════════════════════════════════════════════╝'"
Enter
Type "echo ''"
Enter

Sleep 5s
