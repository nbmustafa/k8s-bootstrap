.PHONY: help bootstrap clean status logs dashboard test

# Default target
.DEFAULT_GOAL := help

# Color codes
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

## help: Display this help message
help:
	@echo "$(BLUE)Kubernetes Sandbox - Available Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Setup & Teardown:$(NC)"
	@echo "  make bootstrap    - Deploy complete sandbox environment"
	@echo "  make clean        - Delete cluster and optionally charts"
	@echo ""
	@echo "$(GREEN)Monitoring:$(NC)"
	@echo "  make status       - Show cluster and application status"
	@echo "  make logs         - Tail logs from all services"
	@echo "  make dashboard    - Open all dashboards in browser"
	@echo ""
	@echo "$(GREEN)Testing:$(NC)"
	@echo "  make test         - Run basic smoke tests"
	@echo "  make validate     - Validate cluster health"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make info         - Display access information"
	@echo "  make shell        - Open kubectl shell"
	@echo ""

## bootstrap: Deploy the complete sandbox environment
bootstrap:
	@echo "$(BLUE)Starting bootstrap process...$(NC)"
	@./bootstrap.sh

## clean: Delete the cluster
clean:
	@echo "$(YELLOW)Cleaning up sandbox environment...$(NC)"
	@./cleanup.sh

## status: Show cluster and application status
status:
	@echo "$(BLUE)Cluster Status:$(NC)"
	@kubectl get nodes
	@echo ""
	@echo "$(BLUE)Namespaces:$(NC)"
	@kubectl get namespaces
	@echo ""
	@echo "$(BLUE)ArgoCD Applications:$(NC)"
	@kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not deployed"
	@echo ""
	@echo "$(BLUE)All Pods:$(NC)"
	@kubectl get pods -A

## logs: Tail logs from all services
logs:
	@echo "$(BLUE)Tailing logs (Ctrl+C to stop)...$(NC)"
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f &
	@kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=50 -f &
	@kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50 -f &
	@wait

## dashboard: Open all dashboards in browser
dashboard:
	@echo "$(GREEN)Opening dashboards...$(NC)"
	@open http://localhost:8080 2>/dev/null || xdg-open http://localhost:8080 2>/dev/null || echo "ArgoCD: http://localhost:8080"
	@open http://localhost:9090 2>/dev/null || xdg-open http://localhost:9090 2>/dev/null || echo "Prometheus: http://localhost:9090"
	@open http://localhost:3000 2>/dev/null || xdg-open http://localhost:3000 2>/dev/null || echo "Grafana: http://localhost:3000"

## test: Run basic smoke tests
test:
	@echo "$(BLUE)Running smoke tests...$(NC)"
	@echo -n "Checking cluster connectivity... "
	@kubectl cluster-info > /dev/null && echo "$(GREEN)✓$(NC)" || echo "$(YELLOW)✗$(NC)"
	@echo -n "Checking ArgoCD... "
	@kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | grep -q Running && echo "$(GREEN)✓$(NC)" || echo "$(YELLOW)✗$(NC)"
	@echo -n "Checking Prometheus... "
	@kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep -q Running && echo "$(GREEN)✓$(NC)" || echo "$(YELLOW)✗$(NC)"
	@echo -n "Checking Grafana... "
	@kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -q Running && echo "$(GREEN)✓$(NC)" || echo "$(YELLOW)✗$(NC)"

## validate: Validate cluster health
validate:
	@echo "$(BLUE)Validating cluster health...$(NC)"
	@kubectl get --raw /healthz
	@kubectl get componentstatuses
	@kubectl top nodes 2>/dev/null || echo "Metrics not available yet"

## info: Display access information
info:
	@echo ""
	@echo "$(BLUE)=== Kubernetes Sandbox Access Information ===$(NC)"
	@echo ""
	@echo "$(GREEN)ArgoCD:$(NC)"
	@echo "  URL: http://localhost:8080"
	@echo "  Username: admin"
	@echo -n "  Password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Not deployed"
	@echo ""
	@echo ""
	@echo "$(GREEN)Prometheus:$(NC)"
	@echo "  URL: http://localhost:9090"
	@echo ""
	@echo "$(GREEN)Grafana:$(NC)"
	@echo "  URL: http://localhost:3000"
	@echo "  Username: admin"
	@echo "  Password: admin"
	@echo ""
	@echo "$(GREEN)Alertmanager:$(NC)"
	@echo "  URL: http://localhost:9093"
	@echo ""

## shell: Open kubectl shell
shell:
	@kubectl config use-context kind-sandbox-cluster
	@bash
