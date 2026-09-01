#!/bin/bash
# Deploy RHEL 10 bootc AMD64 image to OpenShift Virtualization
#
# Prerequisites:
#   - Local: oc login to your SNO cluster
#   - Local: podman/docker authenticated to quay.io
#   - Local: ansible & kubernetes.core collection installed
#   - Quay: AMD64 image available (:dev-amd64 or :prod-amd64)
#   - Quay: AMD64 containerDisk image available (:dev-disk-amd64 or :prod-disk-amd64)
#
# Usage:
#   ./scripts/deploy-to-openshift-virt.sh
#   ./scripts/deploy-to-openshift-virt.sh --image-ref quay.io/waba/bootc-guide:dev-amd64
#   ./scripts/deploy-to-openshift-virt.sh --disk-ref quay.io/waba/bootc-guide:dev-disk-amd64
#
# Environment variables (or use --flags):
#   IMAGE_AMD           - Base AMD64 bootc image (default: quay.io/waba/bootc-guide:dev-amd64)
#   DISK_IMAGE_AMD      - AMD64 containerDisk image (default: quay.io/waba/bootc-guide:dev-disk-amd64)
#   VM_NAME             - VM object name (default: rhel10-bootc-demo)
#   VM_NAMESPACE        - K8s namespace (default: bootc-vms)
#   VM_CORES            - CPU cores (default: 2)
#   VM_MEMORY           - Memory (default: 2Gi)
#   VM_DISK_SIZE        - Disk size (default: 60Gi)
#   VM_STORAGE_CLASS    - Storage class (default: lvms-vg1)
#   SNO_API             - SNO cluster API URL
#   SNO_TOKEN           - SNO cluster auth token

set -euo pipefail

# ============================================================================
# Configuration & Defaults
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load demo-env.sh if it exists for pre-set variables
if [[ -f "$SCRIPT_DIR/demo-env.sh" ]]; then
    source "$SCRIPT_DIR/demo-env.sh"
fi

# Image references (use env vars, or fall back to defaults)
IMAGE_AMD="${IMAGE_AMD:-quay.io/waba/bootc-guide:dev-amd64}"
DISK_IMAGE_AMD="${DISK_IMAGE_AMD:-quay.io/waba/bootc-guide:dev-disk-amd64}"

# VM configuration
VM_NAME="${VM_NAME:-rhel10-bootc-demo}"
VM_NAMESPACE="${VM_NAMESPACE:-bootc-vms}"
VM_CORES="${VM_CORES:-2}"
VM_MEMORY="${VM_MEMORY:-2Gi}"
VM_DISK_SIZE="${VM_DISK_SIZE:-60Gi}"
VM_STORAGE_CLASS="${VM_STORAGE_CLASS:-lvms-vg1}"

# Parse CLI flags (override env vars)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image-ref)
            IMAGE_AMD="$2"
            shift 2
            ;;
        --disk-ref)
            DISK_IMAGE_AMD="$2"
            shift 2
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --namespace)
            VM_NAMESPACE="$2"
            shift 2
            ;;
        --help)
            sed -n '1,/# Usage:/p' "$0" | sed '1d; /^$/d'
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Utility Functions
# ============================================================================

log_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶️  $*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_warning() {
    echo "⚠️  $*"
}

log_error() {
    echo "❌ $*"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_section "Pre-flight Checks"

# Check for required commands
for cmd in oc ansible ansible-playbook; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is not installed"
        exit 1
    fi
done

# Check oc login status
if ! oc cluster-info &> /dev/null; then
    log_error "Not logged in to an OpenShift cluster"
    echo "Run: oc login https://api.your-cluster.example.com --token=<token>"
    exit 1
fi

log_success "OpenShift cluster connectivity OK"

# Check podman/docker auth to quay.io
if ! grep -q "quay.io" ~/.docker/config.json 2>/dev/null; then
    log_warning "No Quay.io credentials found in ~/.docker/config.json"
    log_info "Run: podman login quay.io"
fi

# Verify image references
log_info "Image reference: $IMAGE_AMD"
log_info "Disk image reference: $DISK_IMAGE_AMD"

# ============================================================================
# Stage 1: Verify Images Exist on Quay
# ============================================================================

log_section "Verifying Images on Quay"

verify_image() {
    local image_ref="$1"
    local image_name="${image_ref%%:*}"
    local image_tag="${image_ref##*:}"
    
    if podman inspect "$image_ref" &> /dev/null; then
        log_success "Image found locally: $image_ref"
    else
        log_info "Pulling $image_ref from Quay..."
        if podman pull "$image_ref" &> /dev/null; then
            log_success "Image verified: $image_ref"
        else
            log_error "Failed to pull image: $image_ref"
            log_info "Ensure:"
            log_info "  1. Image exists on Quay"
            log_info "  2. You have authenticated to quay.io: podman login quay.io"
            exit 1
        fi
    fi
}

verify_image "$IMAGE_AMD"
verify_image "$DISK_IMAGE_AMD"

# ============================================================================
# Stage 2: Run Ansible Playbook to Provision VM
# ============================================================================

log_section "Provisioning VM on OpenShift Virtualization"

log_info "Running ansible-playbook provision-vm.yml..."
log_info "  disk_image=$DISK_IMAGE_AMD"
log_info "  vm_name=$VM_NAME"
log_info "  vm_namespace=$VM_NAMESPACE"
log_info "  vm_cores=$VM_CORES"
log_info "  vm_memory=$VM_MEMORY"
log_info "  vm_disk_size=$VM_DISK_SIZE"
log_info "  vm_storage_class=$VM_STORAGE_CLASS"

if ansible-playbook "$REPO_ROOT/ansible/provision-vm.yml" \
    -e "disk_image=$DISK_IMAGE_AMD" \
    -e "vm_name=$VM_NAME" \
    -e "vm_namespace=$VM_NAMESPACE" \
    -e "vm_cores=$VM_CORES" \
    -e "vm_memory=$VM_MEMORY" \
    -e "vm_disk_size=$VM_DISK_SIZE" \
    -e "vm_storage_class=$VM_STORAGE_CLASS"; then
    log_success "VM provisioning completed successfully"
else
    log_error "Ansible playbook failed"
    exit 1
fi

# ============================================================================
# Stage 3: Verify VM is Running & Display Connection Info
# ============================================================================

log_section "VM Status & Connection Info"

# Wait a moment for VM to settle
sleep 5

# Get VM details
VM_INFO=$(oc get vmi "$VM_NAME" -n "$VM_NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")

if [[ -n "$VM_INFO" ]]; then
    log_success "VM is running!"
    echo ""
    echo "  🖥️  VM Name: $VM_NAME"
    echo "  📍 Namespace: $VM_NAMESPACE"
    echo "  🌐 IP Address: $VM_INFO"
    echo ""
    echo "  🔌 Connect via SSH:"
    echo "     ssh demo@$VM_INFO"
    echo ""
    echo "  📊 Check VM status:"
    echo "     oc get vmi -n $VM_NAMESPACE"
    echo ""
    echo "  📊 Check DataVolume import progress:"
    echo "     oc get dv -n $VM_NAMESPACE"
    echo ""
    echo "  📺 View VM console:"
    echo "     virtctl console $VM_NAME -n $VM_NAMESPACE"
    echo ""
else
    log_warning "VM IP address not yet available. It may still be booting."
    echo ""
    echo "  Check status with:"
    echo "    oc get vmi -n $VM_NAMESPACE"
    echo "    oc get dv -n $VM_NAMESPACE"
fi

# ============================================================================
# Summary
# ============================================================================

log_section "Deployment Summary"

echo ""
echo "📦 Deployed Image:"
echo "   $DISK_IMAGE_AMD"
echo ""
echo "🖥️  VM Details:"
echo "   Name: $VM_NAME"
echo "   Namespace: $VM_NAMESPACE"
echo "   CPU: $VM_CORES cores"
echo "   Memory: $VM_MEMORY"
echo "   Disk: $VM_DISK_SIZE"
echo ""
echo "⏭️  Next Steps:"
echo "   1. Wait for DataVolume import to complete (can take 5-10 minutes)"
echo "   2. Get VM IP: oc get vmi -n $VM_NAMESPACE"
echo "   3. SSH into VM: ssh demo@<IP>"
echo "   4. Check bootc status: sudo bootc status"
echo "   5. To upgrade: ansible-playbook ansible/upgrade-vm.yml"
echo ""

log_success "Deployment script completed!"
