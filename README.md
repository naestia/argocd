# Local GitOps Setup — k3s + ArgoCD

A complete GitOps setup for running a local Kubernetes cluster on a separate machine in the same network, fully portable to EKS later.

## 🎯 Overview

This repository implements the **App of Apps** pattern with ArgoCD. All platform tools and applications are declared here as the single source of truth.

- **Cluster**: k3s on a dedicated Linux host
- **GitOps Engine**: ArgoCD
- **Ingress**: ingress-nginx
- **Secrets**: Sealed Secrets
- **Apps**: Two sample nginx apps (app-a, app-b)

## 📁 Repository Structure

```
.
├── bootstrap/
│   └── root-app.yaml          # Root Application (App of Apps)
├── platform/
│   ├── ingress-nginx/
│   │   └── application.yaml   # NGINX Ingress Controller
│   └── sealed-secrets/
│       └── application.yaml   # Sealed Secrets Controller
└── apps/
    ├── app-a/
    │   ├── application.yaml
    │   └── manifests/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── ingress.yaml
    └── app-b/
        ├── application.yaml
        └── manifests/
            ├── deployment.yaml
            ├── service.yaml
            └── ingress.yaml
```

## 🚀 Setup Instructions

### Prerequisites

- A Linux machine on your local network (cluster machine)
- Your main development machine (Mac/Linux/Windows)
- kubectl and helm installed on your main machine
- argocd CLI installed on your main machine
- GitHub account

### Step 1: Push to GitHub

First, push this repository to GitHub:

```bash
# Update the repoURL in bootstrap/root-app.yaml with your GitHub username/org
sed -i 's/YOU/your-github-username/g' bootstrap/root-app.yaml
sed -i 's/YOU/your-github-username/g' apps/*/application.yaml

# Create a new GitHub repository named 'gitops-local'
# Then push:
git add .
git commit -m "Initial GitOps setup

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git branch -M main
git remote add origin https://github.com/your-github-username/gitops-local.git
git push -u origin main
```

### Step 2: Install k3s on Cluster Machine

SSH into your cluster machine and run:

```bash
# Install k3s with Traefik disabled (we'll use NGINX ingress instead)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

# Verify the node is ready
kubectl get nodes

# Print the kubeconfig (you'll need this on your main machine)
cat /etc/rancher/k3s/k3s.yaml
```

Note the cluster machine's local IP address (e.g., `192.168.1.x`).

### Step 3: Configure Remote kubectl Access

On your main machine:

```bash
# Copy kubeconfig from cluster machine (replace CLUSTER_IP with actual IP)
scp user@CLUSTER_IP:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config

# Replace 127.0.0.1 with the cluster machine's LAN IP
sed -i 's/127.0.0.1/CLUSTER_IP/g' ~/.kube/k3s-config

# Point kubectl at the new config
export KUBECONFIG=~/.kube/k3s-config

# Verify remote access
kubectl get nodes
```

Add the `export KUBECONFIG` line to your `~/.bashrc` or `~/.zshrc` to persist.

### Step 4: Bootstrap ArgoCD

On your main machine:

```bash
# Add the ArgoCD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
kubectl create namespace argocd
helm install argocd argo/argo-cd -n argocd

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

# Port-forward the ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443 &

# Get the initial admin password
argocd admin initial-password -n argocd
```

ArgoCD UI will be accessible at `https://CLUSTER_IP:8080` (accept the self-signed cert warning).

### Step 5: Connect ArgoCD to GitHub

```bash
# Login to ArgoCD CLI
argocd login CLUSTER_IP:8080 --insecure

# Register the GitOps repo (replace with your details)
argocd repo add https://github.com/your-github-username/gitops-local \
  --username YOUR_GITHUB_USER \
  --password YOUR_GITHUB_PAT

# Verify the repo is connected
argocd repo list
```

**Alternative (SSH Deploy Key)**:
```bash
argocd repo add git@github.com:your-github-username/gitops-local \
  --ssh-private-key-path ~/.ssh/id_ed25519
```

### Step 6: Apply the Root App of Apps

```bash
# Apply the root Application manifest
kubectl apply -f bootstrap/root-app.yaml -n argocd

# Watch ArgoCD sync all discovered applications
argocd app list

# Watch sync status live (optional)
argocd app wait --all
```

This single command triggers ArgoCD to discover and sync:
- ingress-nginx
- sealed-secrets
- app-a
- app-b

### Step 7: Configure Local DNS

Add these lines to `/etc/hosts` on your main machine (replace with actual cluster IP):

```
192.168.1.x   app-a.local
192.168.1.x   app-b.local
```

**Alternative**: For long-term use, consider running **dnsmasq** or **Pi-hole** on your network to handle `*.local` as a wildcard DNS.

### Step 8: Verify Everything Works

- [ ] **Cluster accessible remotely** — `kubectl get nodes` returns Ready
- [ ] **ArgoCD UI reachable** — https://CLUSTER_IP:8080 loads
- [ ] **Platform synced** — `kubectl get pods -n ingress-nginx` and `kubectl get pods -n kube-system | grep sealed-secrets` show running pods
- [ ] **Apps synced** — `kubectl get pods -n app-a` and `kubectl get pods -n app-b` show running pods
- [ ] **Ingress routing works** — http://app-a.local and http://app-b.local return responses
- [ ] **Drift detection works** — `kubectl delete deployment app-a -n app-a` and watch ArgoCD restore it
- [ ] **Git-driven deploy works** — Push a change to a manifest in Git and watch ArgoCD pick it up within ~3 minutes

## 🎨 Sample Applications

### App A
- **URL**: http://app-a.local
- **Description**: Purple gradient with "Hello from App A"
- **Replicas**: 2

### App B
- **URL**: http://app-b.local
- **Description**: Pink gradient with "Hello from App B"
- **Replicas**: 2

## 🔄 Making Changes

To deploy a new app or make changes:

1. Create or modify manifests in the repository
2. Commit and push to GitHub
3. ArgoCD automatically detects changes within ~3 minutes
4. Changes are applied to the cluster

**Manual sync** (if you don't want to wait):
```bash
argocd app sync app-a
```

## 🛠️ Troubleshooting

### ArgoCD not syncing
```bash
# Check ArgoCD application status
argocd app get app-a

# Check application logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force sync
argocd app sync app-a --force
```

### Ingress not working
```bash
# Check ingress-nginx pods
kubectl get pods -n ingress-nginx

# Check ingress resources
kubectl get ingress -A

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Can't access apps
```bash
# Verify /etc/hosts has the correct IP
cat /etc/hosts | grep local

# Check if ingress-nginx is listening on port 80
kubectl get svc -n ingress-nginx
```

## 🚢 Migration to EKS

When moving to EKS, the repository structure stays identical. Only the platform layer changes:

| Concern | Local (k3s) | AWS (EKS) |
|---------|-------------|-----------|
| Cluster provisioning | k3s install script | Terraform + eksctl |
| Ingress controller | ingress-nginx | AWS LB Controller |
| Secrets management | Sealed Secrets | ESO + Secrets Manager |
| Storage | k3s local-path | EBS CSI driver |
| DNS | /etc/hosts or dnsmasq | ExternalDNS + Route53 |
| Container registry | Docker Hub / GHCR | ECR |
| **ArgoCD** | ✅ Identical | ✅ Identical |
| **App manifests** | ✅ No changes | ✅ No changes |

## 📚 Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [k3s Documentation](https://docs.k3s.io/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Sealed Secrets](https://sealed-secrets.netlify.app/)

## 📝 License

This is a template repository. Feel free to use it as a starting point for your own GitOps setup.
