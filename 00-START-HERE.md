# 🚀 Kubernetes Sandbox Bootstrap - Start Here!

Welcome to your complete Kubernetes sandbox environment with GitOps!

## What You Have

A production-ready, single-script solution that deploys:
- ✅ **Kind Cluster** - Local Kubernetes cluster
- ✅ **ArgoCD** - GitOps continuous delivery
- ✅ **Prometheus** - Metrics and monitoring
- ✅ **Grafana** - Dashboards and visualization
- ✅ **Alertmanager** - Alert management

All accessible via localhost ports with local Helm charts!

## Quick Start (Choose One)

### Option 1: Standard Bootstrap (Fastest)
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

### Option 2: GitOps Bootstrap (Best for Learning)
```bash
chmod +x bootstrap-gitops.sh
./bootstrap-gitops.sh
```

### Option 3: Using Make (Most Convenient)
```bash
make bootstrap
```

## What Happens Next?

The script will:
1. ✅ Check prerequisites (Docker, kubectl, Helm, Kind)
2. ✅ Download Helm charts locally
3. ✅ Create Kind cluster with port mappings
4. ✅ Deploy ArgoCD
5. ✅ Deploy Prometheus & Grafana
6. ✅ Display access information

**Time**: 5-10 minutes

## Access Your Services

After bootstrap completes:

| Service | URL | Credentials |
|---------|-----|-------------|
| **ArgoCD** | http://localhost:8080 | User: `admin`<br>Password: See script output |
| **Prometheus** | http://localhost:9090 | No auth |
| **Grafana** | http://localhost:3000 | User: `admin`<br>Password: `admin` |
| **Alertmanager** | http://localhost:9093 | No auth |

## Prerequisites

Make sure you have these installed:
- Docker Desktop (or Docker Engine)
- kubectl
- Helm 3
- Kind

**Don't have them?** See `QUICKSTART.md` for installation instructions.

## File Guide

| File | Purpose |
|------|---------|
| `QUICKSTART.md` | ⭐ **START HERE** - 5-minute setup guide |
| `README.md` | Complete documentation |
| `ARCHITECTURE.md` | Technical deep dive |
| `PROJECT_STRUCTURE.md` | File organization guide |
| `bootstrap.sh` | Main deployment script |
| `bootstrap-gitops.sh` | GitOps-enabled version |
| `validate.sh` | Health check script |
| `cleanup.sh` | Teardown script |
| `Makefile` | Convenience commands |
| `examples/` | Sample configurations |

## Common Commands

```bash
# View cluster status
make status

# Open all dashboards
make dashboard

# Run health checks
./validate.sh

# View logs
make logs

# Clean up everything
make clean
# or
./cleanup.sh
```

## Next Steps

1. **First Time?** Read `QUICKSTART.md`
2. **Want Details?** Read `README.md`
3. **Customize?** Check `PROJECT_STRUCTURE.md`
4. **Learn Architecture?** Read `ARCHITECTURE.md`

## Troubleshooting

If something goes wrong:

1. Check prerequisites are installed
2. Ensure Docker is running
3. Run `./validate.sh` for diagnostics
4. See troubleshooting in `README.md`

## Examples Included

- `examples/custom-alerts.yaml` - Prometheus alerting rules
- `examples/sample-argocd-app.yaml` - Deploy apps via ArgoCD
- `examples/grafana-dashboards.md` - Dashboard configuration

## Getting Help

1. Check `README.md` troubleshooting section
2. Run `./validate.sh` for diagnostics
3. Review `QUICKSTART.md` for common issues

## Production Considerations

⚠️ **This is a development environment!**

For production, you need:
- TLS/SSL certificates
- External authentication
- Persistent storage
- High availability
- Network policies
- Security scanning
- Backup strategies

See `ARCHITECTURE.md` for details.

---

## Ready to Start?

```bash
# Make scripts executable (if needed)
chmod +x *.sh

# Run bootstrap
./bootstrap.sh

# Wait 5-10 minutes...

# Access ArgoCD
open http://localhost:8080
```

**Have fun building! 🎉**
