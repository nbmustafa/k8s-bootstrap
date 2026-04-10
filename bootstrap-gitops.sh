#!/bin/bash

###############################################################################
# Kubernetes Sandbox Bootstrap Script - GitOps Edition
# This version creates a local git repository for true GitOps workflow
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="sandbox-cluster"
ARGOCD_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/helm-charts"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
GITOPS_REPO="${SCRIPT_DIR}/gitops-repo"

###############################################################################
# Helper Functions
###############################################################################

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v kind &> /dev/null; then
        missing_tools+=("kind")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    log_success "All prerequisites met!"
}

create_directory_structure() {
    log_info "Creating directory structure..."
    
    mkdir -p "${CHARTS_DIR}"/{argocd,prometheus,grafana}
    mkdir -p "${MANIFESTS_DIR}"/{argocd-apps,configs}
    mkdir -p "${GITOPS_REPO}"/{apps,system}
    
    log_success "Directory structure created"
}

initialize_gitops_repo() {
    log_info "Initializing GitOps repository..."
    
    cd "${GITOPS_REPO}"
    
    if [ ! -d .git ]; then
        git init
        git config user.name "Platform Engineer"
        git config user.email "platform@example.com"
        
        # Create initial structure
        mkdir -p apps/monitoring
        mkdir -p system/argocd
        
        # Create README
        cat > README.md << 'GITOPSREADME'
# GitOps Repository

This repository contains all application and system configurations managed by ArgoCD.

## Structure

- `apps/` - Application configurations
  - `monitoring/` - Prometheus and Grafana configurations
- `system/` - System-level configurations
  - `argocd/` - ArgoCD configuration

## Usage

All changes committed to this repository will be automatically synced to the cluster by ArgoCD.
GITOPSREADME
        
        git add .
        git commit -m "Initial commit: GitOps repository structure"
        
        log_success "GitOps repository initialized"
    else
        log_info "GitOps repository already exists"
    fi
    
    cd "${SCRIPT_DIR}"
}

download_helm_charts() {
    log_info "Downloading Helm charts locally..."
    
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    log_info "Downloading ArgoCD chart..."
    helm pull argo/argo-cd --untar --untardir "${CHARTS_DIR}/argocd" --version 7.7.12
    
    log_info "Downloading Prometheus chart..."
    helm pull prometheus-community/kube-prometheus-stack --untar --untardir "${CHARTS_DIR}/prometheus" --version 67.6.0
    
    log_success "Helm charts downloaded successfully"
}

create_helm_values() {
    log_info "Creating Helm values files..."
    
    # ArgoCD values
    cat > "${GITOPS_REPO}/system/argocd/values.yaml" << 'ARGOCDVALUES'
global:
  domain: argocd.localhost

server:
  service:
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443
  extraArgs:
    - --insecure
  
configs:
  params:
    server.insecure: true
  
  cm:
    timeout.reconciliation: 30s
    application.instanceLabelKey: argocd.argoproj.io/instance

dex:
  enabled: false

notifications:
  enabled: false

applicationSet:
  enabled: true

redis-ha:
  enabled: false

controller:
  replicas: 1

repoServer:
  replicas: 1
ARGOCDVALUES
    
    # Prometheus values
    cat > "${GITOPS_REPO}/apps/monitoring/prometheus-values.yaml" << 'PROMVALUES'
prometheus:
  prometheusSpec:
    replicas: 1
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
  service:
    type: NodePort
    nodePort: 30081

alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: 1
  service:
    type: NodePort
    nodePort: 30083

grafana:
  enabled: true
  adminPassword: admin
  service:
    type: NodePort
    nodePort: 30082
  persistence:
    enabled: true
    size: 5Gi
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
        access: proxy
        isDefault: false
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860
        revision: 27
        datasource: Prometheus

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true

prometheusOperator:
  enabled: true
PROMVALUES
    
    # Commit to git
    cd "${GITOPS_REPO}"
    git add .
    git commit -m "Add Helm values for ArgoCD and monitoring stack" || true
    cd "${SCRIPT_DIR}"
    
    log_success "Helm values created and committed"
}

create_kind_cluster() {
    log_info "Creating Kind cluster: ${CLUSTER_NAME}..."
    
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster ${CLUSTER_NAME} already exists. Deleting..."
        kind delete cluster --name "${CLUSTER_NAME}"
    fi
    
    cat << KINDCONFIG | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
    protocol: TCP
  - containerPort: 30443
    hostPort: 8443
    protocol: TCP
  - containerPort: 30081
    hostPort: 9090
    protocol: TCP
  - containerPort: 30082
    hostPort: 3000
    protocol: TCP
  - containerPort: 30083
    hostPort: 9093
    protocol: TCP
  extraMounts:
  - hostPath: ${GITOPS_REPO}
    containerPath: /gitops-repo
    readOnly: true
KINDCONFIG
    
    log_success "Kind cluster created successfully"
    
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    log_success "Cluster is ready"
}

deploy_argocd() {
    log_info "Deploying ArgoCD..."
    
    kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    helm upgrade --install argocd \
        "${CHARTS_DIR}/argocd/argo-cd" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --values "${GITOPS_REPO}/system/argocd/values.yaml" \
        --wait \
        --timeout 10m
    
    log_success "ArgoCD deployed successfully"
    
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s
    
    log_success "ArgoCD is ready"
}

create_argocd_applications() {
    log_info "Creating ArgoCD Application manifests..."
    
    kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create App of Apps pattern
    cat > "${GITOPS_REPO}/system/argocd/root-app.yaml" << ROOTAPP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: file:///gitops-repo
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
ROOTAPP
    
    # Create Prometheus Application
    cat > "${GITOPS_REPO}/apps/monitoring/prometheus-app.yaml" << PROMAPP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: file:///gitops-repo
    targetRevision: HEAD
    path: apps/monitoring
    helm:
      valueFiles:
        - prometheus-values.yaml
      releaseName: prometheus-stack
  destination:
    server: https://kubernetes.default.svc
    namespace: ${MONITORING_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
PROMAPP
    
    # Add chart to gitops repo
    cp -r "${CHARTS_DIR}/prometheus/kube-prometheus-stack" "${GITOPS_REPO}/apps/monitoring/"
    
    # Commit to git
    cd "${GITOPS_REPO}"
    git add .
    git commit -m "Add ArgoCD applications for monitoring stack" || true
    cd "${SCRIPT_DIR}"
    
    log_success "ArgoCD Application manifests created"
}

deploy_via_argocd() {
    log_info "Deploying applications via ArgoCD..."
    
    # Apply the monitoring application directly
    kubectl apply -f "${GITOPS_REPO}/apps/monitoring/prometheus-app.yaml"
    
    log_info "Waiting for ArgoCD to sync applications..."
    sleep 10
    
    # Wait for sync
    kubectl wait --for=condition=Synced application/prometheus-stack \
        -n "${ARGOCD_NAMESPACE}" --timeout=600s || log_warn "Application sync timeout (this is normal, check ArgoCD UI)"
    
    log_success "Applications deployed via ArgoCD"
}

get_argocd_password() {
    kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d
}

display_access_info() {
    local argocd_password
    argocd_password=$(get_argocd_password)
    
    echo ""
    echo "=========================================================================="
    echo -e "${GREEN}Kubernetes GitOps Sandbox Environment Ready!${NC}"
    echo "=========================================================================="
    echo ""
    echo -e "${BLUE}Cluster Information:${NC}"
    echo "  Cluster Name: ${CLUSTER_NAME}"
    echo "  Context: kind-${CLUSTER_NAME}"
    echo "  GitOps Repo: ${GITOPS_REPO}"
    echo ""
    echo -e "${BLUE}ArgoCD:${NC}"
    echo "  URL: http://localhost:8080"
    echo "  Username: admin"
    echo "  Password: ${argocd_password}"
    echo ""
    echo -e "${BLUE}Prometheus:${NC}"
    echo "  URL: http://localhost:9090"
    echo ""
    echo -e "${BLUE}Grafana:${NC}"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
    echo -e "${BLUE}Alertmanager:${NC}"
    echo "  URL: http://localhost:9093"
    echo ""
    echo "=========================================================================="
    echo -e "${YELLOW}GitOps Workflow:${NC}"
    echo "  1. Make changes in: ${GITOPS_REPO}"
    echo "  2. Commit changes: cd ${GITOPS_REPO} && git add . && git commit -m 'update'"
    echo "  3. ArgoCD will auto-sync within 3 minutes"
    echo "  4. Or manually sync in ArgoCD UI"
    echo "=========================================================================="
    echo ""
}

cleanup_on_error() {
    log_error "An error occurred during setup. Cleaning up..."
    kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
    exit 1
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo ""
    echo "=========================================================================="
    echo -e "${GREEN}Kubernetes GitOps Sandbox Bootstrap${NC}"
    echo -e "${BLUE}Production-Ready Platform Engineering${NC}"
    echo "=========================================================================="
    echo ""
    
    trap cleanup_on_error ERR
    
    check_prerequisites
    create_directory_structure
    initialize_gitops_repo
    download_helm_charts
    create_helm_values
    create_kind_cluster
    deploy_argocd
    create_argocd_applications
    deploy_via_argocd
    display_access_info
    
    log_success "Bootstrap completed successfully!"
}

main "$@"
