# Module 0: Environment Setup

## Objective

Prepare the workshop environment by verifying your EKS cluster, installing prerequisites, and creating your Git repository.

## Outcome

By the end of this module, you will have:

- ✔ A working EKS cluster
- ✔ AWS Load Balancer Controller installed
- ✔ A CodeCommit repository
- ✔ A local Git working directory

---

## 0.1 Verify the Environment

Your EKS cluster has already been provisioned. Let's verify access.

```bash
# Check which cluster you're connected to
kubectl config current-context

# Switch to the workshop cluster
aws eks update-kubeconfig --name eks-workshop

# List worker nodes (should show Ready)
kubectl get nodes

# List namespaces
kubectl get ns

# List all running pods across namespaces
kubectl get pods -A
```

**Quick orientation:**

| Component | What it is |
|-----------|-----------|
| Control Plane | Managed by AWS (you don't see these pods) |
| Worker Nodes | EC2 instances running your workloads |
| kube-system | Namespace for cluster infrastructure components |
| default | Namespace where resources go if you don't specify one |

---

## 0.2 Download the Bootstrap Script

```bash
curl -O https://raw.githubusercontent.com/devanshpoplii/argocd-immersion-day/main/0-environment/bootstrap.sh
chmod +x bootstrap.sh
```

---

## 0.3 Bootstrap the Environment

Rather than performing several infrastructure tasks manually, the bootstrap script sets everything up.

```bash
./bootstrap.sh
```

**What the script does:**

| Step | Action |
|------|--------|
| 1 | Installs AWS Load Balancer Controller |
| 2 | Creates CodeCommit repository |

Wait for the script to complete before proceeding.

---

## 0.4 Clone the Repository

Clone the repository created during bootstrap:

```bash
git clone codecommit::us-west-2://argocd-workshop
cd argocd-workshop
```

This repository will become the **single source of truth** for everything deployed by ArgoCD throughout the workshop.

Right now, it's empty. Every manifest you create during the workshop will be committed and pushed here.

**Initialize with a README:**

```bash
echo "# ArgoCD Workshop" > README.md
git add .
git commit -m "Initial commit"
git push
```

---

## End State

At the end of Module 0, you should have:

- ✔ Connected to the EKS cluster
- ✔ AWS Load Balancer Controller installed
- ✔ CodeCommit repository created
- ✔ Local Git repository cloned and initialized
- ✔ Ready to install ArgoCD
