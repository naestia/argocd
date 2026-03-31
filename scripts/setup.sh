#!/bin/bash
set -e

# Local GitOps Setup Helper Script
# This script helps automate the setup process

CLUSTER_IP="${CLUSTER_IP:-}"
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_PAT="${GITHUB_PAT:-}"

echo "======================================"
echo "Local GitOps Setup - Helper Script"
echo "======================================"
echo

# Check prerequisites
check_prerequisites() {
  echo "Checking prerequisites..."

  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting."; exit 1; }
  command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting."; exit 1; }
  command -v argocd >/dev/null 2>&1 || { echo "argocd CLI is required but not installed. Aborting."; exit 1; }

  echo "✓ All prerequisites installed"
  echo
}

# Get cluster IP
get_cluster_ip() {
  if [ -z "$CLUSTER_IP" ]; then
    read -p "Enter your k3s cluster machine IP address: " CLUSTER_IP
  fi
  echo "Using cluster IP: $CLUSTER_IP"
  echo
}

# Install ArgoCD
install_argocd() {
  echo "Installing ArgoCD..."

  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update

  kubectl create namespace argocd || true
  helm install argocd argo/argo-cd -n argocd || echo "ArgoCD already installed"

  echo "Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

  echo "✓ ArgoCD installed successfully"
  echo
}

# Get ArgoCD password
get_argocd_password() {
  echo "Getting ArgoCD admin password..."
  ARGOCD_PASSWORD=$(argocd admin initial-password -n argocd | head -n 1)
  echo "ArgoCD admin password: $ARGOCD_PASSWORD"
  echo
}

# Connect repo
connect_repo() {
  if [ -z "$GITHUB_USER" ]; then
    read -p "Enter your GitHub username: " GITHUB_USER
  fi

  if [ -z "$GITHUB_PAT" ]; then
    read -sp "Enter your GitHub Personal Access Token: " GITHUB_PAT
    echo
  fi

  echo "Logging into ArgoCD..."
  argocd login $CLUSTER_IP:8080 --insecure --username admin --password "$ARGOCD_PASSWORD"

  echo "Registering GitHub repository..."
  argocd repo add https://github.com/$GITHUB_USER/gitops-local \
    --username $GITHUB_USER \
    --password $GITHUB_PAT

  echo "✓ Repository connected"
  echo
}

# Apply root app
apply_root_app() {
  echo "Applying root Application..."
  kubectl apply -f bootstrap/root-app.yaml -n argocd

  echo "Waiting for applications to sync..."
  sleep 5
  argocd app list

  echo
  echo "✓ Root application applied"
  echo
}

# Main menu
show_menu() {
  echo "What would you like to do?"
  echo "1) Full setup (ArgoCD + Repo + Root App)"
  echo "2) Install ArgoCD only"
  echo "3) Connect GitHub repo"
  echo "4) Apply root Application"
  echo "5) Show ArgoCD password"
  echo "6) Port-forward ArgoCD UI"
  echo "7) Check status"
  echo "0) Exit"
  echo
  read -p "Select option: " option

  case $option in
    1)
      check_prerequisites
      get_cluster_ip
      install_argocd
      get_argocd_password
      connect_repo
      apply_root_app
      ;;
    2)
      check_prerequisites
      install_argocd
      get_argocd_password
      ;;
    3)
      get_cluster_ip
      get_argocd_password
      connect_repo
      ;;
    4)
      apply_root_app
      ;;
    5)
      get_argocd_password
      ;;
    6)
      echo "Starting port-forward on 8080..."
      kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
      ;;
    7)
      echo "Cluster nodes:"
      kubectl get nodes
      echo
      echo "ArgoCD applications:"
      argocd app list
      echo
      echo "All pods:"
      kubectl get pods -A
      ;;
    0)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo "Invalid option"
      ;;
  esac
}

# Run
show_menu
