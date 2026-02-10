# Project Structure

## Complete Directory Layout

```
kubernetes-sandbox-bootstrap/
│
├── bootstrap.sh                 # Main bootstrap script (simple version)
├── bootstrap-gitops.sh          # GitOps-enabled bootstrap script
├── cleanup.sh                   # Cluster cleanup script
├── validate.sh                  # Validation and testing script
├── Makefile                     # Convenience commands
│
├── README.md                    # Comprehensive documentation
├── QUICKSTART.md                # Quick start guide
├── ARCHITECTURE.md              # Architecture documentation
├── PROJECT_STRUCTURE.md         # This file
│
├── .gitignore                   # Git ignore patterns
│
├── examples/                    # Example configurations
│   ├── custom-alerts.yaml       # Prometheus alert examples
│   ├── sample-argocd-app.yaml   # ArgoCD application examples
│   └── grafana-dashboards.md    # Dashboard configuration guide
│
├── helm-charts/                 # Downloaded Helm charts (created at runtime)
│   ├── argocd/
│   │   ├── argo-cd/            # ArgoCD chart
│   │   └── values.yaml         # Custom ArgoCD values
│   ├── prometheus/
│   │   ├── kube-prometheus-stack/  # Prometheus Operator chart
│   │   └── values.yaml         # Custom Prometheus values
│   └── grafana/
│       └── grafana/            # Grafana chart (optional)
│
├── manifests/                   # Kubernetes manifests (created at runtime)
│   ├── argocd-apps/
│   │   └── prometheus-app.yaml # ArgoCD Application for Prometheus
│   └── configs/
│       └── (additional configs)
│
└── gitops-repo/                 # Local GitOps repository (GitOps version only)
    ├── .git/
    ├── README.md
    ├── apps/
    │   └── monitoring/
    │       ├── kube-prometheus-stack/  # Prometheus chart copy
    │       ├── prometheus-values.yaml
    │       └── prometheus-app.yaml
    └── system/
        └── argocd/
            ├── values.yaml
            └── root-app.yaml
```

## File Descriptions

### Core Scripts

| File | Purpose | When to Use |
|------|---------|------------|
| `bootstrap.sh` | Standard bootstrap with Helm | First time setup, quick testing |
| `bootstrap-gitops.sh` | GitOps-enabled bootstrap | Learning GitOps, production pattern |
| `cleanup.sh` | Cluster and resource cleanup | Teardown environment |
| `validate.sh` | Health checks and tests | Verify deployment, troubleshooting |

### Documentation

| File | Content | Audience |
|------|---------|----------|
| `README.md` | Complete guide with all features | Everyone |
| `QUICKSTART.md` | 5-minute setup guide | First-time users |
| `ARCHITECTURE.md` | Technical architecture details | Platform engineers, SREs |
| `PROJECT_STRUCTURE.md` | This file | Developers customizing |

### Configuration Files

| File | Purpose | Customization |
|------|---------|--------------|
| `Makefile` | Convenient CLI commands | Add your own targets |
| `.gitignore` | Git exclusions | Adjust as needed |
| `helm-charts/*/values.yaml` | Helm chart configurations | Primary customization point |

### Examples

| File | Demonstrates | Usage |
|------|-------------|-------|
| `examples/custom-alerts.yaml` | Prometheus alerting rules | Copy and modify |
| `examples/sample-argocd-app.yaml` | ArgoCD applications | Template for new apps |
| `examples/grafana-dashboards.md` | Dashboard configuration | Reference guide |

## Generated/Runtime Directories

These are created when you run the bootstrap scripts:

### helm-charts/
- **Created by**: Bootstrap scripts
- **Contains**: Downloaded Helm charts and custom values
- **Git Tracking**: Charts ignored, values tracked
- **Purpose**: Local storage of Helm charts for offline use

### manifests/
- **Created by**: Bootstrap scripts
- **Contains**: ArgoCD application definitions
- **Git Tracking**: Can be tracked
- **Purpose**: Kubernetes manifests for applications

### gitops-repo/ (GitOps version only)
- **Created by**: `bootstrap-gitops.sh`
- **Contains**: Git-tracked configurations
- **Git Tracking**: Separate git repository
- **Purpose**: Source of truth for GitOps workflow

## Usage Patterns

### Pattern 1: Quick Start (No Customization)

```bash
# Clone repository
git clone <repo-url>
cd kubernetes-sandbox-bootstrap

# Run bootstrap
./bootstrap.sh

# Access services
# ArgoCD: http://localhost:8080
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000
```

### Pattern 2: Customized Deployment

```bash
# 1. Modify values before bootstrap
vim helm-charts/prometheus/values.yaml  # This will be created by script

# 2. Run bootstrap
./bootstrap.sh

# 3. Validate
./validate.sh

# 4. Add custom alerts
kubectl apply -f examples/custom-alerts.yaml
```

### Pattern 3: GitOps Workflow

```bash
# 1. Run GitOps bootstrap
./bootstrap-gitops.sh

# 2. Make changes to configuration
cd gitops-repo/apps/monitoring
vim prometheus-values.yaml

# 3. Commit changes
git add .
git commit -m "Increase retention to 14 days"

# 4. ArgoCD auto-syncs (within 3 minutes)
# Or manually sync in UI: http://localhost:8080
```

### Pattern 4: Development Workflow

```bash
# Daily workflow
make status              # Check cluster health
make dashboard          # Open all dashboards
make logs              # View logs

# Deploy your app
kubectl apply -f examples/sample-argocd-app.yaml

# Cleanup
make clean
```

## Customization Points

### 1. Resource Limits

Edit `helm-charts/prometheus/values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m        # Increase for better performance
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 8Gi
```

### 2. Retention Policies

```yaml
prometheus:
  prometheusSpec:
    retention: 14d      # Increase retention period
    retentionSize: 20GB # Set size limit
```

### 3. Additional Dashboards

```yaml
grafana:
  dashboards:
    default:
      my-dashboard:
        gnetId: 12345   # Grafana.com dashboard ID
        revision: 1
        datasource: Prometheus
```

### 4. Alert Rules

Create `manifests/configs/custom-alerts.yaml` or use examples.

### 5. Port Mappings

Edit the Kind cluster config in `bootstrap.sh`:

```bash
extraPortMappings:
- containerPort: 30090  # Add new port
  hostPort: 8090
  protocol: TCP
```

## Extension Points

### Adding New Applications

1. **Via ArgoCD**:
   - Create Application manifest in `manifests/argocd-apps/`
   - Apply: `kubectl apply -f manifests/argocd-apps/my-app.yaml`

2. **Via Helm**:
   - Download chart to `helm-charts/my-app/`
   - Create values file
   - Install: `helm install my-app helm-charts/my-app/chart -f values.yaml`

3. **Via GitOps** (gitops version):
   - Add to `gitops-repo/apps/`
   - Commit and push
   - ArgoCD auto-syncs

### Adding Monitoring for Custom Apps

1. Add ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
```

2. Application exposes metrics on `/metrics`
3. Prometheus automatically scrapes
4. View in Prometheus: `my_app_*`

### Adding Custom Grafana Dashboards

1. Create dashboard in Grafana UI
2. Export as JSON
3. Create ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    { ... dashboard JSON ... }
```

4. Apply: `kubectl apply -f my-dashboard-configmap.yaml`
5. Dashboard auto-loads

## Troubleshooting Common Issues

### Issue: Bootstrap fails

**Check**:
```bash
# Prerequisites
docker info
kubectl version
helm version
kind version

# Logs
cat /tmp/bootstrap.log
```

### Issue: Services not accessible

**Check**:
```bash
# Port mappings
docker ps | grep kind

# Services
kubectl get svc -A

# Pods
kubectl get pods -A
```

### Issue: Pods not starting

**Check**:
```bash
# Resources
docker stats

# Pod events
kubectl describe pod <pod-name> -n <namespace>

# Logs
kubectl logs <pod-name> -n <namespace>
```

## Best Practices

### 1. Version Control
- Track `values.yaml` files in Git
- Don't track downloaded Helm charts
- Use `.gitignore` appropriately

### 2. Configuration Management
- Keep sensitive data out of Git
- Use Kubernetes Secrets or Sealed Secrets
- Document configuration changes

### 3. Testing
- Run `validate.sh` after changes
- Test in non-production first
- Use `make test` for quick checks

### 4. Maintenance
- Regular `helm repo update`
- Review and update chart versions
- Clean up unused resources

### 5. Security
- Change default passwords
- Enable TLS in production
- Implement RBAC
- Regular security scanning

## Support & Resources

### Getting Help
1. Check `README.md` troubleshooting section
2. Run `./validate.sh` for diagnostics
3. Review logs: `make logs`
4. Check official documentation

### Contributing
1. Fork repository
2. Create feature branch
3. Make changes
4. Test thoroughly
5. Submit pull request

### Additional Resources
- Official Kubernetes docs
- ArgoCD documentation
- Prometheus best practices
- Grafana tutorials
- CNCF projects

---

**Remember**: This is a development environment. Production deployments require additional security, reliability, and scalability considerations. See `ARCHITECTURE.md` for details.
