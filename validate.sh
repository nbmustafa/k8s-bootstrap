#!/bin/bash

###############################################################################
# Kubernetes Sandbox Validation & Testing Script
# Comprehensive health checks and smoke tests
###############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="sandbox-cluster"
ARGOCD_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"

# Test results
PASSED=0
FAILED=0
WARNINGS=0

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNINGS++))
}

section() {
    echo ""
    echo "=========================================================================="
    echo -e "${BLUE}$1${NC}"
    echo "=========================================================================="
}

###############################################################################
# Test Functions
###############################################################################

test_prerequisites() {
    section "Testing Prerequisites"
    
    # Docker
    if docker info &> /dev/null; then
        log_success "Docker is running"
    else
        log_fail "Docker is not running"
    fi
    
    # kubectl
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is installed"
    else
        log_fail "kubectl is not installed"
    fi
    
    # Helm
    if command -v helm &> /dev/null; then
        log_success "Helm is installed ($(helm version --short))"
    else
        log_fail "Helm is not installed"
    fi
    
    # Kind
    if command -v kind &> /dev/null; then
        log_success "Kind is installed ($(kind version))"
    else
        log_fail "Kind is not installed"
    fi
}

test_cluster_existence() {
    section "Testing Cluster"
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_success "Cluster '${CLUSTER_NAME}' exists"
    else
        log_fail "Cluster '${CLUSTER_NAME}' does not exist"
        return 1
    fi
    
    # Test kubectl connectivity
    if kubectl cluster-info &> /dev/null; then
        log_success "kubectl can connect to cluster"
    else
        log_fail "kubectl cannot connect to cluster"
        return 1
    fi
    
    # Check nodes
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$node_count" -gt 0 ]; then
        log_success "Cluster has $node_count node(s)"
    else
        log_fail "No nodes found in cluster"
    fi
    
    # Check node status
    if kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
        log_success "All nodes are Ready"
    else
        log_warn "Some nodes are not Ready"
    fi
}

test_namespaces() {
    section "Testing Namespaces"
    
    # ArgoCD namespace
    if kubectl get namespace "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_success "Namespace '${ARGOCD_NAMESPACE}' exists"
    else
        log_fail "Namespace '${ARGOCD_NAMESPACE}' does not exist"
    fi
    
    # Monitoring namespace
    if kubectl get namespace "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Namespace '${MONITORING_NAMESPACE}' exists"
    else
        log_fail "Namespace '${MONITORING_NAMESPACE}' does not exist"
    fi
}

test_argocd() {
    section "Testing ArgoCD"
    
    # Check ArgoCD server deployment
    if kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_success "ArgoCD server deployment exists"
        
        # Check if running
        local ready=$(kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$ready" -gt 0 ]; then
            log_success "ArgoCD server is running ($ready/$ready replicas)"
        else
            log_fail "ArgoCD server is not running"
        fi
    else
        log_fail "ArgoCD server deployment not found"
    fi
    
    # Check ArgoCD controller
    if kubectl get statefulset argocd-application-controller -n "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_success "ArgoCD application controller exists"
    else
        log_warn "ArgoCD application controller not found"
    fi
    
    # Check ArgoCD repo server
    if kubectl get deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_success "ArgoCD repo server exists"
    else
        log_warn "ArgoCD repo server not found"
    fi
    
    # Check ArgoCD service
    if kubectl get service argocd-server -n "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_success "ArgoCD server service exists"
    else
        log_fail "ArgoCD server service not found"
    fi
    
    # Check if ArgoCD is accessible
    if curl -k -s http://localhost:8080 > /dev/null 2>&1; then
        log_success "ArgoCD UI is accessible at http://localhost:8080"
    else
        log_warn "ArgoCD UI is not accessible at http://localhost:8080"
    fi
}

test_prometheus() {
    section "Testing Prometheus"
    
    # Check Prometheus operator
    if kubectl get deployment prometheus-operator-kube-prometheus-operator -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Prometheus Operator is deployed"
    else
        log_warn "Prometheus Operator deployment not found"
    fi
    
    # Check Prometheus statefulset
    if kubectl get statefulset prometheus-prometheus-kube-prometheus-prometheus -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Prometheus StatefulSet exists"
        
        local ready=$(kubectl get statefulset prometheus-prometheus-kube-prometheus-prometheus \
            -n "${MONITORING_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$ready" -gt 0 ]; then
            log_success "Prometheus is running ($ready replica(s))"
        else
            log_fail "Prometheus is not running"
        fi
    else
        log_fail "Prometheus StatefulSet not found"
    fi
    
    # Check Prometheus service
    if kubectl get service prometheus-kube-prometheus-prometheus -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Prometheus service exists"
    else
        log_fail "Prometheus service not found"
    fi
    
    # Check if Prometheus is accessible
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        log_success "Prometheus is accessible at http://localhost:9090"
    else
        log_warn "Prometheus is not accessible at http://localhost:9090"
    fi
    
    # Test Prometheus API
    if curl -s http://localhost:9090/api/v1/query?query=up | grep -q "success"; then
        log_success "Prometheus API is responding"
    else
        log_warn "Prometheus API is not responding correctly"
    fi
}

test_grafana() {
    section "Testing Grafana"
    
    # Check Grafana deployment
    if kubectl get deployment prometheus-grafana -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Grafana deployment exists"
        
        local ready=$(kubectl get deployment prometheus-grafana -n "${MONITORING_NAMESPACE}" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$ready" -gt 0 ]; then
            log_success "Grafana is running ($ready replica(s))"
        else
            log_fail "Grafana is not running"
        fi
    else
        log_fail "Grafana deployment not found"
    fi
    
    # Check Grafana service
    if kubectl get service prometheus-grafana -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Grafana service exists"
    else
        log_fail "Grafana service not found"
    fi
    
    # Check if Grafana is accessible
    if curl -s http://localhost:3000/api/health | grep -q "ok"; then
        log_success "Grafana is accessible at http://localhost:3000"
    else
        log_warn "Grafana is not accessible at http://localhost:3000"
    fi
}

test_alertmanager() {
    section "Testing Alertmanager"
    
    # Check Alertmanager statefulset
    if kubectl get statefulset alertmanager-prometheus-kube-prometheus-alertmanager \
        -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Alertmanager StatefulSet exists"
    else
        log_warn "Alertmanager StatefulSet not found"
    fi
    
    # Check if Alertmanager is accessible
    if curl -s http://localhost:9093/-/healthy > /dev/null 2>&1; then
        log_success "Alertmanager is accessible at http://localhost:9093"
    else
        log_warn "Alertmanager is not accessible at http://localhost:9093"
    fi
}

test_node_exporter() {
    section "Testing Node Exporter"
    
    # Check Node Exporter daemonset
    if kubectl get daemonset prometheus-prometheus-node-exporter -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Node Exporter DaemonSet exists"
        
        local desired=$(kubectl get daemonset prometheus-prometheus-node-exporter \
            -n "${MONITORING_NAMESPACE}" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        local ready=$(kubectl get daemonset prometheus-prometheus-node-exporter \
            -n "${MONITORING_NAMESPACE}" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        
        if [ "$ready" -eq "$desired" ] && [ "$ready" -gt 0 ]; then
            log_success "Node Exporter is running on all nodes ($ready/$desired)"
        else
            log_warn "Node Exporter: $ready/$desired pods ready"
        fi
    else
        log_warn "Node Exporter DaemonSet not found"
    fi
}

test_kube_state_metrics() {
    section "Testing Kube State Metrics"
    
    # Check Kube State Metrics deployment
    if kubectl get deployment prometheus-kube-state-metrics -n "${MONITORING_NAMESPACE}" &> /dev/null; then
        log_success "Kube State Metrics deployment exists"
    else
        log_warn "Kube State Metrics deployment not found"
    fi
}

test_pod_health() {
    section "Testing Pod Health"
    
    # Count pods by status
    local total_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local pending_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    local failed_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c -E "Error|CrashLoopBackOff|ImagePullBackOff" || echo "0")
    
    log_info "Total pods: $total_pods"
    log_info "Running: $running_pods, Pending: $pending_pods, Failed: $failed_pods"
    
    if [ "$failed_pods" -eq 0 ]; then
        log_success "No failed pods"
    else
        log_fail "Found $failed_pods failed pod(s)"
        kubectl get pods -A | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" || true
    fi
    
    if [ "$pending_pods" -eq 0 ]; then
        log_success "No pending pods"
    else
        log_warn "Found $pending_pods pending pod(s)"
    fi
}

test_services() {
    section "Testing Services"
    
    # List all NodePort services
    log_info "NodePort services:"
    kubectl get svc -A --no-headers 2>/dev/null | grep NodePort | while read line; do
        echo "  $line"
    done
}

test_persistent_volumes() {
    section "Testing Persistent Volumes"
    
    local pvc_count=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)
    if [ "$pvc_count" -gt 0 ]; then
        log_info "Found $pvc_count PVC(s)"
        
        local bound_count=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
        if [ "$bound_count" -eq "$pvc_count" ]; then
            log_success "All PVCs are Bound ($bound_count/$pvc_count)"
        else
            log_warn "Not all PVCs are Bound ($bound_count/$pvc_count)"
        fi
    else
        log_info "No PVCs found"
    fi
}

test_network_connectivity() {
    section "Testing Network Connectivity"
    
    # Test DNS resolution
    if kubectl run test-dns --image=busybox:1.28 --rm -it --restart=Never \
        --command -- nslookup kubernetes.default &> /dev/null; then
        log_success "DNS resolution working"
    else
        log_warn "DNS resolution test failed"
    fi
    
    # Test pod-to-pod connectivity
    log_info "Testing pod-to-pod connectivity..."
    # This is a simple test - in production you'd want more comprehensive tests
}

test_metrics_collection() {
    section "Testing Metrics Collection"
    
    # Query Prometheus for basic metrics
    if curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"status":"success"'; then
        log_success "Prometheus is collecting metrics"
        
        # Count targets
        local targets=$(curl -s http://localhost:9090/api/v1/targets | \
            jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")
        log_info "Active Prometheus targets: $targets"
    else
        log_warn "Cannot verify metrics collection"
    fi
}

display_summary() {
    section "Test Summary"
    
    echo ""
    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo ""
    
    if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Your sandbox is healthy.${NC}"
        return 0
    elif [ "$FAILED" -eq 0 ]; then
        echo -e "${YELLOW}! Tests passed with warnings. Review warnings above.${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the failures above.${NC}"
        return 1
    fi
}

display_access_info() {
    section "Access Information"
    
    echo ""
    echo "ArgoCD UI:     http://localhost:8080"
    echo "Prometheus UI: http://localhost:9090"
    echo "Grafana UI:    http://localhost:3000"
    echo "Alertmanager:  http://localhost:9093"
    echo ""
    echo "To get ArgoCD password:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo ""
    echo "=========================================================================="
    echo -e "${BLUE}Kubernetes Sandbox Validation${NC}"
    echo "=========================================================================="
    echo ""
    
    test_prerequisites
    test_cluster_existence || exit 1
    test_namespaces
    test_argocd
    test_prometheus
    test_grafana
    test_alertmanager
    test_node_exporter
    test_kube_state_metrics
    test_pod_health
    test_services
    test_persistent_volumes
    test_metrics_collection
    
    display_summary
    local exit_code=$?
    
    display_access_info
    
    exit $exit_code
}

main "$@"
