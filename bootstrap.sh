#!/bin/bash

###############################################################################
# Kubernetes Sandbox Bootstrap Script
# Principal Platform Engineer - Production Ready GitOps Environment
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
ARGOCD_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/helm-charts"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

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
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools:"
        log_info "  Docker: https://docs.docker.com/get-docker/"
        log_info "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        log_info "  Helm: https://helm.sh/docs/intro/install/"
        log_info "  Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
    
    # Check if Docker daemon is running
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
    
    log_success "Directory structure created"
}

download_helm_charts() {
    log_info "Downloading Helm charts locally..."
    
    # Add Helm repositories
    log_info "Adding Helm repositories..."
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Download ArgoCD chart
    log_info "Downloading ArgoCD chart..."
    helm pull argo/argo-cd --untar --untardir "${CHARTS_DIR}/argocd" --version 9.5.0
    
    # Download Prometheus chart
    log_info "Downloading Prometheus chart..."
    helm pull prometheus-community/kube-prometheus-stack --untar --untardir "${CHARTS_DIR}/prometheus" --version 83.4.0
    
    # Download Grafana chart (standalone, though prometheus-stack includes it)
    log_info "Downloading Grafana chart..."
    helm pull grafana/grafana --untar --untardir "${CHARTS_DIR}/grafana" --version 10.5.15
    
    log_success "Helm charts downloaded successfully"
}

create_kind_cluster() {
    log_info "Creating Kind cluster: ${CLUSTER_NAME}..."
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster ${CLUSTER_NAME} already exists. Deleting..."
        kind delete cluster --name "${CLUSTER_NAME}"
    fi
    
    # Create Kind cluster with config
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
KINDCONFIG
    
    log_success "Kind cluster created successfully"
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "Cluster is ready"
}

create_argocd_values() {
    log_info "Creating ArgoCD values file..."
    
    cat > "${CHARTS_DIR}/argocd/values.yaml" << 'ARGOCDVALUES'
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
    
    log_success "ArgoCD values created"
}

create_prometheus_values() {
    log_info "Creating Prometheus values file..."
    
    cat > "${CHARTS_DIR}/prometheus/values.yaml" << 'PROMVALUES'
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
      prometheus-stats:
        gnetId: 2
        revision: 2
        datasource: Prometheus

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true

prometheusOperator:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
PROMVALUES
    
    log_success "Prometheus values created"
}

deploy_argocd() {
    log_info "Deploying ArgoCD..."
    
    # Create namespace
    kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD using local Helm chart
    helm upgrade --install argocd \
        "${CHARTS_DIR}/argocd/argo-cd" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --values "${CHARTS_DIR}/argocd/values.yaml" \
        --wait \
        --timeout 10m
    
    log_success "ArgoCD deployed successfully"
    
    # Wait for ArgoCD server to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s
    
    log_success "ArgoCD is ready"
}

create_argocd_applications() {
    log_info "Creating ArgoCD Application manifests..."
    
    # Create monitoring namespace
    kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Prometheus Application
    cat > "${MANIFESTS_DIR}/argocd-apps/prometheus-app.yaml" << PROMAPP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: file://${CHARTS_DIR}/prometheus/kube-prometheus-stack
    targetRevision: HEAD
    helm:
      valueFiles:
        - file://${CHARTS_DIR}/prometheus/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${MONITORING_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
PROMAPP
    
    log_success "ArgoCD Application manifests created"
}

deploy_monitoring_stack() {
    log_info "Deploying monitoring stack via ArgoCD..."
    
    # Note: Since ArgoCD can't access local filesystem directly, we'll deploy using Helm directly
    # but keep the ArgoCD Application for demonstration
    
    log_info "Deploying Prometheus Stack..."
    helm upgrade --install prometheus-stack \
        "${CHARTS_DIR}/prometheus/kube-prometheus-stack" \
        --namespace "${MONITORING_NAMESPACE}" \
        --values "${CHARTS_DIR}/prometheus/values.yaml" \
        --create-namespace \
        --wait \
        --timeout 15m
    
    log_success "Monitoring stack deployed successfully"
}

get_argocd_password() {
    log_info "Retrieving ArgoCD admin password..."
    
    local password
    password=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)
    
    echo "${password}"
}

display_access_info() {
    log_info "Gathering access information..."
    
    local argocd_password
    argocd_password=$(get_argocd_password)
    
    echo ""
    echo "=========================================================================="
    echo -e "${GREEN}Kubernetes Sandbox Environment Ready!${NC}"
    echo "=========================================================================="
    echo ""
    echo -e "${BLUE}Cluster Information:${NC}"
    echo "  Cluster Name: ${CLUSTER_NAME}"
    echo "  Context: kind-${CLUSTER_NAME}"
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
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  kubectl get pods -A                    # List all pods"
    echo "  kubectl config use-context kind-${CLUSTER_NAME}  # Switch context"
    echo "  kind delete cluster --name ${CLUSTER_NAME}       # Delete cluster"
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
    echo -e "${GREEN}Kubernetes Sandbox Bootstrap${NC}"
    echo -e "${BLUE}Principal Platform Engineer - Production Ready Environment${NC}"
    echo "=========================================================================="
    echo ""
    
    trap cleanup_on_error ERR
    
    check_prerequisites
    create_directory_structure
    download_helm_charts
    create_argocd_values
    create_prometheus_values
    create_kind_cluster
    deploy_argocd
    create_argocd_applications
    deploy_monitoring_stack
    display_access_info
    
    log_success "Bootstrap completed successfully!"
}

main "$@"
