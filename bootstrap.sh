#!/bin/bash

###############################################################################
# Kubernetes Sandbox Bootstrap Script
# Principal Platform Engineer - Production Ready GitOps Environment
#
# Enhancements:
# - Local GitOps repo under ./gitops-repo
# - Kind node hostPath mount for the local repo
# - ArgoCD repo-server hostPath mount for local GitOps access
# - App-of-Apps root application watching gitops-repo/apps
#
# NOTE:
# - ArgoCD, kube-prometheus-stack, and Grafana deployment remains unchanged
#   in the sense that ArgoCD is still installed via Helm, and the monitoring
#   stack is still installed directly via Helm exactly as before.
# - The GitOps repo enhancement is only for future apps you want ArgoCD to manage.
###############################################################################

set -euo pipefail

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

# Local GitOps repo
GITOPS_REPO_DIR="${SCRIPT_DIR}/gitops-repo"
GITOPS_BOOTSTRAP_DIR="${GITOPS_REPO_DIR}/bootstrap"
GITOPS_APPS_DIR="${GITOPS_REPO_DIR}/apps"
GITOPS_ROOT_APP_FILE="${GITOPS_BOOTSTRAP_DIR}/root-app.yaml"
GITOPS_REPO_MOUNT_PATH="/gitops-repo"

# Git identity for local repo bootstrap
GIT_USER_NAME="sandbox-bootstrap"
GIT_USER_EMAIL="sandbox-bootstrap@localhost"

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
        log_info "Please install missing tools:"
        log_info "  Docker: https://docs.docker.com/get-docker/"
        log_info "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        log_info "  Helm: https://helm.sh/docs/intro/install/"
        log_info "  Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        log_info "  Git: https://git-scm.com/downloads"
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
    mkdir -p "${GITOPS_BOOTSTRAP_DIR}"
    mkdir -p "${GITOPS_APPS_DIR}"

    log_success "Directory structure created"
}

initialize_gitops_repo() {
    log_info "Initializing local GitOps repository..."

    if [ ! -d "${GITOPS_REPO_DIR}/.git" ]; then
        git init "${GITOPS_REPO_DIR}" >/dev/null
        log_success "Initialized new Git repository at ${GITOPS_REPO_DIR}"
    else
        log_warn "Git repository already exists at ${GITOPS_REPO_DIR}"
    fi

    # Set local-only git identity so commits work on fresh machines
    git -C "${GITOPS_REPO_DIR}" config user.name "${GIT_USER_NAME}"
    git -C "${GITOPS_REPO_DIR}" config user.email "${GIT_USER_EMAIL}"
    git -C "${GITOPS_REPO_DIR}" branch -M main >/dev/null 2>&1 || true

    # Ignore common local artifacts
    cat > "${GITOPS_REPO_DIR}/.gitignore" << 'GITIGNORE'
# Local editor / OS artifacts
.DS_Store
*.swp
*.swo
*.tmp

# Optional local build artifacts
dist/
build/
GITIGNORE

    # Human-friendly repo README
    cat > "${GITOPS_REPO_DIR}/README.md" << EOF
# Local GitOps Repo

This repository is the local source of truth for future ArgoCD-managed apps.

## Layout

- \`bootstrap/\` — bootstrap manifests, including the root App-of-Apps Application
- \`apps/\` — future ArgoCD Application manifests

## Usage

Add a new ArgoCD Application manifest under \`apps/\`, commit it to this local repo,
and ArgoCD will detect it through the root application.

## Local Mount

This repository is mounted into the Kind node and into the ArgoCD repo-server so
ArgoCD can read it directly from the local filesystem.
EOF

    # Placeholder file for future app manifests
    cat > "${GITOPS_APPS_DIR}/README.md" << 'APPSREADME'
# Future ArgoCD Applications

Place ArgoCD Application manifests in this directory.

Example structure:

- apps/team-a/my-app.yaml
- apps/platform/another-service.yaml

The root application watches this directory and recursively syncs any manifests found here.
APPSREADME

    # Create the App-of-Apps root application
    cat > "${GITOPS_ROOT_APP_FILE}" << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-root
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: file://${GITOPS_REPO_MOUNT_PATH}
    targetRevision: HEAD
    path: apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

    # Git add/commit if there are any changes
    git -C "${GITOPS_REPO_DIR}" add .

    if ! git -C "${GITOPS_REPO_DIR}" diff --cached --quiet; then
        git -C "${GITOPS_REPO_DIR}" commit -m "Initial bootstrap of local GitOps repo" >/dev/null
        log_success "Committed initial GitOps repository content"
    else
        log_warn "No new GitOps repository changes to commit"
    fi

    # Make sure files are readable by the repo-server container
    chmod -R a+rX "${GITOPS_REPO_DIR}"

    log_success "Local GitOps repository is ready"
}

# download_helm_charts() {
#     log_info "Downloading Helm charts locally..."

#     # Add Helm repositories
#     log_info "Adding Helm repositories..."
#     helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
#     helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
#     helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
#     helm repo update >/dev/null

#     # Download ArgoCD chart
#     log_info "Downloading ArgoCD chart..."
#     helm pull argo/argo-cd --untar --untardir "${CHARTS_DIR}/argocd" --version 9.5.0

#     # Download Prometheus chart
#     log_info "Downloading Prometheus chart..."
#     helm pull prometheus-community/kube-prometheus-stack --untar --untardir "${CHARTS_DIR}/prometheus" --version 83.4.0

#     # Download Grafana chart (standalone, though prometheus-stack includes it)
#     log_info "Downloading Grafana chart..."
#     helm pull grafana/grafana --untar --untardir "${CHARTS_DIR}/grafana" --version 10.5.15

#     log_success "Helm charts downloaded successfully"
# }

download_chart_if_missing() {
    local chart_name=$1
    local repo_chart=$2
    local version=$3
    local target_dir=$4

    if [ -d "${target_dir}/${chart_name}" ]; then
        log_warn "Chart ${chart_name} already exists. Skipping download."
    else
        log_info "Downloading ${chart_name}..."
        helm pull "${repo_chart}" \
            --untar \
            --untardir "${target_dir}" \
            --version "${version}"
        log_success "${chart_name} downloaded"
    fi
}

download_chart_if_missing() {
    local chart_name=$1
    local repo_chart=$2
    local version=$3
    local target_dir=$4

    if [ -d "${target_dir}/${chart_name}" ]; then
        log_warn "Chart ${chart_name} already exists. Skipping download."
    else
        log_info "Downloading ${chart_name}..."
        helm pull "${repo_chart}" \
            --untar \
            --untardir "${target_dir}" \
            --version "${version}"
        log_success "${chart_name} downloaded"
    fi
}

download_helm_charts() {
    log_info "Preparing Helm charts..."

    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
    helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
    helm repo update >/dev/null

    download_chart_if_missing "argo-cd" "argo/argo-cd" "9.5.0" "${CHARTS_DIR}/argocd"
    download_chart_if_missing "kube-prometheus-stack" "prometheus-community/kube-prometheus-stack" "83.4.0" "${CHARTS_DIR}/prometheus"
    download_chart_if_missing "grafana" "grafana/grafana" "10.5.15" "${CHARTS_DIR}/grafana"

    log_success "Helm charts ready"
}

create_kind_cluster() {
    log_info "Creating Kind cluster: ${CLUSTER_NAME}..."

    # Check if cluster already exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster ${CLUSTER_NAME} already exists. Deleting..."
        kind delete cluster --name "${CLUSTER_NAME}"
    fi

    # Create Kind cluster with local GitOps repo mounted into the node
    cat << KINDCONFIG | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ${GITOPS_REPO_DIR}
    containerPath: ${GITOPS_REPO_MOUNT_PATH}
    readOnly: false
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

patch_argocd_repo_server_for_local_gitops_repo() {
    log_info "Patching ArgoCD repo-server to mount the local GitOps repository..."

    cat > "${MANIFESTS_DIR}/configs/argocd-repo-server-local-gitops-patch.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: ${ARGOCD_NAMESPACE}
spec:
  template:
    spec:
      volumes:
        - name: gitops-repo
          hostPath:
            path: ${GITOPS_REPO_MOUNT_PATH}
            type: Directory
      containers:
        - name: repo-server
          volumeMounts:
            - name: gitops-repo
              mountPath: ${GITOPS_REPO_MOUNT_PATH}
              readOnly: true
EOF

    kubectl apply -f "${MANIFESTS_DIR}/configs/argocd-repo-server-local-gitops-patch.yaml"
    kubectl rollout status deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout=300s

    log_success "ArgoCD repo-server now has access to the local GitOps repo"
}

deploy_monitoring_stack() {
    log_info "Deploying monitoring stack via Helm..."

    # Keep this deployment path unchanged
    helm upgrade --install prometheus-stack \
        "${CHARTS_DIR}/prometheus/kube-prometheus-stack" \
        --namespace "${MONITORING_NAMESPACE}" \
        --values "${CHARTS_DIR}/prometheus/values.yaml" \
        --create-namespace \
        --wait \
        --timeout 15m

    log_success "Monitoring stack deployed successfully"
}

apply_gitops_root_app() {
    log_info "Applying App-of-Apps root application..."

    kubectl apply -f "${GITOPS_ROOT_APP_FILE}"

    log_success "Root ArgoCD application applied"
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
    echo -e "${BLUE}GitOps Repo:${NC}"
    echo "  Local Path: ${GITOPS_REPO_DIR}"
    echo "  Mounted Into Kind: ${GITOPS_REPO_MOUNT_PATH}"
    echo "  Root App: ${GITOPS_ROOT_APP_FILE}"
    echo "  Future ArgoCD apps: place Application manifests under ${GITOPS_APPS_DIR}"
    echo ""
    echo "=========================================================================="
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  kubectl get pods -A                         # List all pods"
    echo "  kubectl config use-context kind-${CLUSTER_NAME}   # Switch context"
    echo "  kind delete cluster --name ${CLUSTER_NAME}         # Delete cluster"
    echo "  git -C ${GITOPS_REPO_DIR} log --oneline     # View local GitOps history"
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
    initialize_gitops_repo
    download_helm_charts
    create_argocd_values
    create_prometheus_values
    create_kind_cluster
    deploy_argocd
    patch_argocd_repo_server_for_local_gitops_repo
    deploy_monitoring_stack
    apply_gitops_root_app
    display_access_info

    log_success "Bootstrap completed successfully!"
}

main "$@"
