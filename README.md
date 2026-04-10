# Kubernetes Sandbox Bootstrap

A single-script solution for deploying a complete Kubernetes sandbox environment with GitOps capabilities.

## 🎯 Features

- **One-Command Setup**: Single script deploys everything
- **Local Helm Charts**: All charts downloaded and stored locally - no external dependencies during deployment
- **GitOps Ready**: ArgoCD for declarative application management
- **Full Monitoring Stack**: Prometheus + Grafana with pre-configured dashboards
- **Port Forwarding**: All services accessible via localhost
- **Production Patterns**: Best practices from enterprise platform engineering
- **Self-Contained**: Runs completely offline after initial chart download

## 📋 Prerequisites

Before running the bootstrap script, ensure you have the following tools installed:

| Tool | Version | Installation Guide |
|------|---------|-------------------|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| kubectl | 1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.12+ | https://helm.sh/docs/intro/install/ |
| Kind | 0.20+ | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |

### Quick Install (macOS/Linux)

```bash
# macOS (using Homebrew)
brew install docker kubectl helm kind

# Linux (using package manager)
# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

## 🚀 Quick Start

1. **Clone or download this repository**
   ```bash
   git clone <your-repo>
   cd <your-repo>
   ```

2. **Run the bootstrap script**
   ```bash
   ./bootstrap.sh
   ```

3. **Access your services** (displayed at end of bootstrap)
   - ArgoCD: http://localhost:8080
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000
   - Alertmanager: http://localhost:9093

## 📁 Directory Structure

After running the bootstrap script, you'll have:

```
.
├── bootstrap.sh                    # Main bootstrap script
├── cleanup.sh                      # Cluster cleanup script
├── README.md                       # This file
├── helm-charts/                    # Local Helm charts
│   ├── argocd/
│   │   ├── argo-cd/               # ArgoCD Helm chart
│   │   └── values.yaml            # Custom ArgoCD values
│   ├── prometheus/
│   │   ├── kube-prometheus-stack/ # Prometheus Operator chart
│   │   └── values.yaml            # Custom Prometheus values
│   └── grafana/
│       └── grafana/               # Grafana Helm chart
└── manifests/                      # Kubernetes manifests
    ├── argocd-apps/               # ArgoCD Application definitions
    │   └── prometheus-app.yaml
    └── configs/                    # Additional configurations
```

## 🔧 What Gets Deployed

### 1. Kind Cluster
- **Name**: `sandbox-cluster`
- **Nodes**: 1 control-plane
- **Port Mappings**:
  - 8080 → ArgoCD UI
  - 8443 → ArgoCD HTTPS
  - 9090 → Prometheus
  - 3000 → Grafana
  - 9093 → Alertmanager

### 2. ArgoCD (GitOps Platform)
- **Namespace**: `argocd`
- **Version**: 7.7.12
- **Features**:
  - Automated sync enabled
  - Self-healing enabled
  - ApplicationSet controller
  - Web UI with insecure mode (for local dev)

### 3. Prometheus Stack
- **Namespace**: `monitoring`
- **Version**: 67.6.0
- **Components**:
  - Prometheus Operator
  - Prometheus Server (7d retention)
  - Alertmanager
  - Node Exporter
  - Kube State Metrics
  - Service Monitors

### 4. Grafana
- **Namespace**: `monitoring` (bundled with Prometheus)
- **Version**: Included in kube-prometheus-stack
- **Pre-configured Dashboards**:
  - Kubernetes Cluster Overview (ID: 7249)
  - Node Exporter Full (ID: 1860)
  - Prometheus Stats (ID: 2)
- **Data Source**: Auto-configured Prometheus

## 🔐 Default Credentials

### ArgoCD
- **URL**: http://localhost:8080
- **Username**: `admin`
- **Password**: Retrieved automatically (displayed after bootstrap)
- **Retrieve password**:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```

### Grafana
- **URL**: http://localhost:3000
- **Username**: `admin`
- **Password**: `admin`
- ⚠️ **Change on first login in production!**

## 🛠️ Common Operations

### View All Pods
```bash
kubectl get pods -A
```

### Check ArgoCD Applications
```bash
kubectl get applications -n argocd
```

### Access Prometheus Targets
```bash
open http://localhost:9090/targets
```

### Port Forward Services (if needed)
```bash
# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### View Logs
```bash
# ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100

# Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100
```

## 🧹 Cleanup

### Delete Everything
```bash
./cleanup.sh
```

Or manually:
```bash
kind delete cluster --name sandbox-cluster
```

### Keep Cluster, Remove Applications
```bash
# Remove monitoring stack
helm uninstall -n monitoring prometheus-stack

# Remove ArgoCD
helm uninstall -n argocd argocd

# Delete namespaces
kubectl delete namespace monitoring
kubectl delete namespace argocd
```

## 🔄 Customization

### Modify ArgoCD Configuration
Edit `helm-charts/argocd/values.yaml` before running bootstrap.

### Modify Prometheus/Grafana Configuration
Edit `helm-charts/prometheus/values.yaml` before running bootstrap.

### Change Cluster Configuration
Edit the Kind cluster config in `bootstrap.sh` (look for `KINDCONFIG` section).

### Add More Applications
1. Download Helm chart to `helm-charts/<app-name>/`
2. Create ArgoCD Application in `manifests/argocd-apps/<app-name>-app.yaml`
3. Apply: `kubectl apply -f manifests/argocd-apps/<app-name>-app.yaml`

## 🎓 Advanced Usage

### Add Custom Grafana Dashboards
Edit `helm-charts/prometheus/values.yaml`:

```yaml
grafana:
  dashboards:
    default:
      my-custom-dashboard:
        gnetId: <dashboard-id>
        revision: 1
        datasource: Prometheus
```

### Enable Prometheus Federation
Add to `helm-charts/prometheus/values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'federate'
        scrape_interval: 15s
        honor_labels: true
        metrics_path: '/federate'
        params:
          'match[]':
            - '{job="prometheus"}'
        static_configs:
          - targets:
            - 'prometheus-server.monitoring:9090'
```

### Configure Alerting Rules
Create `manifests/configs/alert-rules.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-alerts
  namespace: monitoring
data:
  custom-rules.yaml: |
    groups:
      - name: custom
        rules:
          - alert: HighPodMemory
            expr: container_memory_usage_bytes > 1000000000
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High memory usage detected"
```

## 🐛 Troubleshooting

### Bootstrap Script Fails
```bash
# Check Docker is running
docker info

# Check Kind installation
kind version

# Check kubectl can connect
kubectl version

# View script output with debug
bash -x ./bootstrap.sh
```

### Pods Not Starting
```bash
# Check pod status
kubectl get pods -n monitoring
kubectl get pods -n argocd

# Describe problematic pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>
```

### Can't Access Services
```bash
# Verify port mappings
docker ps

# Check services
kubectl get svc -n argocd
kubectl get svc -n monitoring

# Verify NodePort services
kubectl get svc -n monitoring -o wide
```

### ArgoCD Application Not Syncing
```bash
# Check application status
kubectl get applications -n argocd

# Describe application
kubectl describe application prometheus-stack -n argocd

# Force sync
kubectl patch application prometheus-stack -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

```bash
cd gitops-repo/apps

# Add new app
vim my-app.yaml

git add .
git commit -m "Add my app"
```

## 📚 Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Contributing

This is a platform engineering reference implementation. Feel free to:

1. Fork and customize for your needs
2. Add additional services
3. Improve automation
4. Share feedback

## 📝 License

This project is provided as-is for educational and development purposes.

## ⚠️ Production Considerations

This sandbox is designed for **local development and testing**. For production:

- [ ] Enable TLS/SSL for all services
- [ ] Implement proper RBAC
- [ ] Use external secrets management
- [ ] Configure persistent storage properly
- [ ] Set up backup and disaster recovery
- [ ] Implement network policies
- [ ] Enable audit logging
- [ ] Use production-grade passwords
- [ ] Configure resource limits and quotas
- [ ] Set up monitoring and alerting rules
- [ ] Implement security scanning
- [ ] Use private container registries

---

**Built with ❤️ by Platform Engineering**
