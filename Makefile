.PHONY: help install connect apply status sync clean

CLUSTER_IP ?= 192.168.1.100
GITHUB_USER ?=

help: ## Show this help message
	@echo "Local GitOps Makefile"
	@echo "===================="
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Variables:"
	@echo "  CLUSTER_IP=$(CLUSTER_IP)    # Set with: make target CLUSTER_IP=192.168.1.x"
	@echo "  GITHUB_USER=$(GITHUB_USER)  # Set with: make target GITHUB_USER=yourname"

install: ## Install ArgoCD on the cluster
	@echo "Installing ArgoCD..."
	helm repo add argo https://argoproj.github.io/argo-helm || true
	helm repo update
	kubectl create namespace argocd || true
	helm install argocd argo/argo-cd -n argocd || echo "ArgoCD already installed"
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
	@echo "✓ ArgoCD installed"
	@echo
	@echo "Admin password:"
	@argocd admin initial-password -n argocd | head -n 1

connect: ## Connect ArgoCD to GitHub repo
	@echo "Connecting to ArgoCD..."
	argocd login $(CLUSTER_IP):8080 --insecure
	@echo "Adding repository..."
	argocd repo add https://github.com/$(GITHUB_USER)/gitops-local
	argocd repo list

apply: ## Apply the root Application
	@echo "Applying root Application..."
	kubectl apply -f bootstrap/root-app.yaml -n argocd
	@echo "Waiting for sync..."
	@sleep 3
	@argocd app list

status: ## Show status of all applications
	@echo "=== Cluster Nodes ==="
	@kubectl get nodes
	@echo
	@echo "=== ArgoCD Applications ==="
	@argocd app list
	@echo
	@echo "=== Platform Pods ==="
	@kubectl get pods -n ingress-nginx
	@kubectl get pods -n kube-system | grep sealed-secrets || true
	@echo
	@echo "=== App Pods ==="
	@kubectl get pods -n app-a || true
	@kubectl get pods -n app-b || true
	@echo
	@echo "=== Ingress Routes ==="
	@kubectl get ingress -A

sync: ## Force sync all applications
	@echo "Syncing all applications..."
	argocd app sync --all

forward: ## Port-forward ArgoCD UI to localhost:8080
	@echo "Port-forwarding ArgoCD UI to https://localhost:8080"
	@echo "Username: admin"
	@echo "Password: $$(argocd admin initial-password -n argocd | head -n 1)"
	@echo
	kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443

password: ## Show ArgoCD admin password
	@argocd admin initial-password -n argocd | head -n 1

logs-argocd: ## Show ArgoCD application controller logs
	kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50 -f

logs-ingress: ## Show ingress-nginx controller logs
	kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 -f

clean: ## Remove ArgoCD and all applications
	@echo "WARNING: This will remove ArgoCD and all applications!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete -f bootstrap/root-app.yaml -n argocd || true; \
		helm uninstall argocd -n argocd || true; \
		kubectl delete namespace argocd || true; \
		kubectl delete namespace ingress-nginx || true; \
		kubectl delete namespace app-a || true; \
		kubectl delete namespace app-b || true; \
		echo "✓ Cleanup complete"; \
	fi
