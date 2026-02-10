#!/bin/bash

###############################################################################
# Kubernetes Sandbox Cleanup Script
# Safely removes the sandbox cluster and optionally downloaded charts
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="sandbox-cluster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/helm-charts"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_cluster() {
    log_info "Checking for cluster: ${CLUSTER_NAME}..."
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Deleting Kind cluster: ${CLUSTER_NAME}..."
        kind delete cluster --name "${CLUSTER_NAME}"
        log_success "Cluster deleted successfully"
    else
        log_warn "Cluster ${CLUSTER_NAME} not found"
    fi
}

cleanup_helm_charts() {
    if [ -d "${CHARTS_DIR}" ]; then
        log_warn "This will delete all downloaded Helm charts in ${CHARTS_DIR}"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing Helm charts..."
            rm -rf "${CHARTS_DIR}"
            log_success "Helm charts removed"
        else
            log_info "Keeping Helm charts"
        fi
    else
        log_info "No Helm charts directory found"
    fi
}

main() {
    echo ""
    echo "=========================================================================="
    echo -e "${YELLOW}Kubernetes Sandbox Cleanup${NC}"
    echo "=========================================================================="
    echo ""
    
    cleanup_cluster
    
    echo ""
    read -p "Do you also want to remove downloaded Helm charts? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_helm_charts
    fi
    
    echo ""
    log_success "Cleanup completed!"
    echo ""
}

main "$@"
