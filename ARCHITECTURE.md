# Architecture Documentation

## Overview

This Kubernetes sandbox provides a complete, production-pattern platform engineering environment for local development, testing, and learning GitOps workflows.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Machine                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Docker Container                        │ │
│  │                  (Kind Control Plane)                      │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │              Kubernetes Cluster                      │ │ │
│  │  │                                                      │ │ │
│  │  │  ┌─────────────────┐    ┌──────────────────────┐   │ │ │
│  │  │  │  argocd NS      │    │  monitoring NS       │   │ │ │
│  │  │  │                 │    │                      │   │ │ │
│  │  │  │  • Server       │    │  • Prometheus        │   │ │ │
│  │  │  │  • Repo Server  │    │  • Grafana           │   │ │ │
│  │  │  │  • Controller   │    │  • Alertmanager      │   │ │ │
│  │  │  │  • ApplicationSet│   │  • Node Exporter     │   │ │ │
│  │  │  │  • Redis        │    │  • Kube State Metrics│   │ │ │
│  │  │  └─────────────────┘    └──────────────────────┘   │ │ │
│  │  │                                                      │ │ │
│  │  │  ┌────────────────────────────────────────────────┐ │ │ │
│  │  │  │         System Components                      │ │ │
│  │  │  │  • kube-system (CoreDNS, etc.)                │ │ │
│  │  │  │  • local-path-provisioner (Storage)           │ │ │
│  │  │  └────────────────────────────────────────────────┘ │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Port Mappings:                                                  │
│  localhost:8080  →  ArgoCD (NodePort 30080)                     │
│  localhost:9090  →  Prometheus (NodePort 30081)                 │
│  localhost:3000  →  Grafana (NodePort 30082)                    │
│  localhost:9093  →  Alertmanager (NodePort 30083)               │
└─────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Kind Cluster

**Purpose**: Local Kubernetes cluster running in Docker

**Configuration**:
- Single control-plane node
- Custom port mappings for service access
- Mounted volumes for GitOps repository (gitops version)
- Node labels for workload scheduling

**Resources**:
- Uses Docker Desktop/Engine resources
- Recommended: 4 CPUs, 8GB RAM

### 2. ArgoCD (GitOps Engine)

**Purpose**: Continuous delivery and GitOps orchestration

**Components**:
```
ArgoCD Architecture:
├── Application Controller (StatefulSet)
│   └── Monitors Git repositories and reconciles application state
├── Repo Server (Deployment)
│   └── Clones and renders manifests from Git/Helm repos
├── Server (Deployment)
│   └── API server and Web UI
├── ApplicationSet Controller (Deployment)
│   └── Manages multiple Applications via generators
└── Redis (Deployment)
    └── Caching and state storage
```

**Configuration**:
- Insecure mode (development only)
- Automated sync policies
- Self-healing enabled
- NodePort service for web access

**GitOps Workflow**:
1. Manifests/Helm charts stored in Git repository
2. ArgoCD monitors repository for changes
3. Automatic or manual sync to cluster
4. Health checks and status reporting
5. Automatic rollback on failure

### 3. Prometheus Stack

**Purpose**: Metrics collection, storage, and alerting

**Components**:

#### Prometheus Operator
```
Prometheus Operator:
├── CRDs:
│   ├── ServiceMonitor: Defines how to scrape metrics from services
│   ├── PodMonitor: Defines how to scrape metrics from pods
│   ├── PrometheusRule: Defines alerting and recording rules
│   └── Probe: Defines blackbox monitoring
└── Operator: Manages Prometheus instances and configuration
```

#### Prometheus Server (StatefulSet)
- **Scraping**: Collects metrics from exporters and services
- **Storage**: Time-series database (7-day retention)
- **Query**: PromQL query engine
- **Alerting**: Rule evaluation and alert generation

#### Alertmanager (StatefulSet)
- **Routing**: Alert routing based on labels
- **Grouping**: Alert aggregation
- **Silencing**: Temporary muting of alerts
- **Notification**: Integration with external systems

#### Exporters
- **Node Exporter**: Hardware and OS metrics
- **Kube State Metrics**: Kubernetes object state metrics

**Data Flow**:
```
Services/Pods (metrics endpoints)
    ↓ (scrape)
Prometheus Server
    ↓ (store)
Time-Series Database
    ↓ (query)
Grafana / API Clients
    ↓ (evaluate)
Alert Rules
    ↓ (fire)
Alertmanager
    ↓ (notify)
External Systems
```

### 4. Grafana

**Purpose**: Metrics visualization and dashboarding

**Features**:
- **Data Sources**: Pre-configured Prometheus connection
- **Dashboards**: Pre-loaded Kubernetes monitoring dashboards
- **Variables**: Template variables for dynamic filtering
- **Annotations**: Event markers from Kubernetes
- **Alerting**: Built-in alerting (in addition to Prometheus)

**Dashboard Types**:
1. Cluster-level: Overall cluster health
2. Node-level: Individual node metrics
3. Namespace-level: Resource usage by namespace
4. Pod-level: Container metrics
5. Application-level: Custom app metrics

### 5. Storage Architecture

```
Storage Stack:
├── local-path-provisioner (Kind default)
│   └── Dynamic PV provisioning using host paths
├── Prometheus PVCs
│   └── Time-series data storage (10Gi)
└── Grafana PVCs
    └── Dashboard and configuration storage (5Gi)
```

**Note**: In Kind, storage is not persistent across cluster deletions.

## Network Architecture

### Service Mesh

```
Pod Network (Kubernetes CNI):
- CIDR: 10.244.0.0/16
- Pod-to-pod communication via CNI
- Service discovery via kube-dns/CoreDNS
```

### Service Types

1. **ClusterIP** (Default):
   - Internal cluster communication
   - Service discovery via DNS
   - Example: prometheus-kube-prometheus-prometheus

2. **NodePort**:
   - External access via node IP:port
   - Port range: 30000-32767
   - Mapped to host via Kind extraPortMappings

3. **LoadBalancer** (Not used):
   - Would require MetalLB or similar
   - Not necessary for local development

### DNS Resolution

```
DNS Hierarchy:
cluster.local
├── <service>.<namespace>.svc.cluster.local
│   └── Example: prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local
└── <pod-ip>.<namespace>.pod.cluster.local
```

## Security Architecture

### RBAC (Role-Based Access Control)

```
RBAC Structure:
├── ServiceAccounts
│   ├── argocd-*: ArgoCD component accounts
│   └── prometheus-*: Prometheus stack accounts
├── ClusterRoles
│   ├── Operator permissions
│   └── Metric collection permissions
└── ClusterRoleBindings
    └── Bind roles to service accounts
```

### Security Considerations (Development)

⚠️ **This is a development environment**. Production requires:

1. **TLS/SSL**: All services should use HTTPS
2. **Authentication**: Integrate with SSO/LDAP
3. **Authorization**: Fine-grained RBAC
4. **Network Policies**: Pod-to-pod communication restrictions
5. **Secrets Management**: External secrets (Vault, Sealed Secrets)
6. **Pod Security**: Pod Security Standards/Policies
7. **Image Security**: Image scanning and signing
8. **Audit Logging**: Kubernetes audit logs enabled

## Data Flow

### Metrics Collection Flow

```
1. Application exposes metrics
   └── HTTP endpoint (e.g., /metrics)
   
2. ServiceMonitor/PodMonitor defines scrape config
   └── Labels, intervals, paths
   
3. Prometheus Operator generates Prometheus config
   └── Automatic config reload
   
4. Prometheus scrapes metrics
   └── Stores in time-series database
   
5. Grafana queries Prometheus
   └── Displays in dashboards
   
6. Alert rules evaluated
   └── Fires alerts to Alertmanager
   
7. Alertmanager processes alerts
   └── Deduplication, grouping, routing
   
8. Notifications sent
   └── Email, Slack, PagerDuty, etc.
```

### GitOps Deployment Flow

```
1. Developer commits to Git repository
   └── Manifests, Helm charts, values
   
2. ArgoCD detects change
   └── Periodic polling or webhook
   
3. ArgoCD repo server clones repo
   └── Renders manifests (Helm, Kustomize, etc.)
   
4. Application controller compares state
   └── Desired (Git) vs Actual (Cluster)
   
5. Sync operation initiated
   └── Automatic or manual
   
6. Resources applied to cluster
   └── kubectl apply-like behavior
   
7. Health checks performed
   └── Custom health assessments
   
8. Status updated in ArgoCD UI
   └── Synced, Healthy, Progressing, Degraded
```

## Scalability Considerations

### Current Configuration (Single Node)

- **Workload**: Development and testing
- **Limitations**:
  - Single point of failure
  - Resource constraints
  - No high availability

### Production Scaling

For production, consider:

1. **Multi-node cluster**:
   - 3+ control plane nodes
   - 3+ worker nodes
   - Separate etcd cluster

2. **Prometheus**:
   - Federation for multiple Prometheus instances
   - Thanos for long-term storage and global view
   - Prometheus replicas for HA

3. **ArgoCD**:
   - HA mode with multiple replicas
   - Redis HA cluster
   - Application controller sharding

4. **Grafana**:
   - Multiple replicas behind load balancer
   - External database (PostgreSQL)
   - Read-only replicas

5. **Storage**:
   - Network-attached storage (NFS, Ceph, etc.)
   - Storage classes with replication
   - Regular backups

## Monitoring & Observability

### Metrics Types

1. **Infrastructure Metrics**:
   - Node CPU, Memory, Disk, Network
   - Kubernetes API server metrics
   - etcd metrics

2. **Application Metrics**:
   - Pod CPU, Memory usage
   - Container metrics
   - Custom application metrics

3. **Service Metrics**:
   - Request rate, latency, errors (RED)
   - Saturation metrics

### Logging (Not Included)

For production, add:
- **Log Collection**: Fluentd, Fluent Bit, or Vector
- **Log Storage**: Elasticsearch, Loki
- **Log Visualization**: Kibana, Grafana

### Tracing (Not Included)

For production, add:
- **Tracing**: Jaeger, Tempo
- **Instrumentation**: OpenTelemetry
- **Service Mesh**: Istio, Linkerd

## Disaster Recovery

### Backup Strategy (Production)

1. **etcd Snapshots**: Regular automated backups
2. **Persistent Data**: Volume snapshots
3. **Configuration**: Git as source of truth
4. **Metrics**: Long-term storage (Thanos, Cortex)

### Recovery Procedures

1. **Cluster Failure**: Restore from etcd snapshot
2. **Application Failure**: ArgoCD re-sync from Git
3. **Data Loss**: Restore from volume snapshots

## Performance Tuning

### Prometheus

```yaml
# Optimize for high cardinality
scrape_interval: 30s  # Reduce frequency if needed
evaluation_interval: 30s

# Storage optimization
retention: 7d  # Adjust based on needs
storage:
  tsdb:
    min_block_duration: 2h
    max_block_duration: 2h
```

### ArgoCD

```yaml
# Increase sync frequency
timeout.reconciliation: 30s  # Default: 180s

# Application controller tuning
controller:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
```

### Grafana

```yaml
# Caching
caching:
  enabled: true
  
# Query optimization
dataproxy:
  timeout: 300
  keep_alive_seconds: 300
```

## References

### Official Documentation
- [Kubernetes](https://kubernetes.io/docs/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Kind](https://kind.sigs.k8s.io/)
- [Helm](https://helm.sh/docs/)

### Best Practices
- [12 Factor Apps](https://12factor.net/)
- [GitOps Principles](https://opengitops.dev/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Kubernetes Patterns](https://www.redhat.com/en/resources/oreilly-kubernetes-patterns-ebook)

### Community Resources
- [CNCF Landscape](https://landscape.cncf.io/)
- [Kubernetes SIGs](https://github.com/kubernetes-sigs)
- [Prometheus Community](https://prometheus.io/community/)
