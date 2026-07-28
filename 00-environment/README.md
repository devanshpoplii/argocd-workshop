# 🏗️ Module 0: Environment Setup

<p align="center">
  <img src="https://img.shields.io/badge/Duration-30%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Beginner-green" />
  <img src="https://img.shields.io/badge/Module-0%20of%207-orange" />
</p>

---

## 🎯 Objective

Prepare the workshop environment by verifying your EKS cluster, installing prerequisites, and creating your Git repository.

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

> [!TIP]
> **Quick orientation:**
>
> | Component | What it is |
> |-----------|-----------|
> | Control Plane | Managed by AWS (you don't see these pods) |
> | Worker Nodes | EC2 instances running your workloads |
> | kube-system | Namespace for cluster infrastructure components |
> | default | Namespace where resources go if you don't specify one |

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

> [!IMPORTANT]
> Wait for the script to complete before proceeding.

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

> [!NOTE]
> If `git push` asks for credentials, ensure `git-remote-codecommit` was installed by the bootstrap script.

---

<details>
<summary>🔧 Troubleshooting</summary>

| Problem | Solution |
|---------|----------|
| `kubectl` not connecting | Run `aws eks update-kubeconfig --name eks-workshop` |
| Bootstrap script fails on LB controller | Check IAM permissions on the IDE role |
| `git clone` fails | Ensure `pip install git-remote-codecommit` ran successfully |
| CodeCommit access denied | Add `AWSCodeCommitPowerUser` policy to your IDE role via CloudShell |

</details>

---

## ✅ End State

At the end of Module 0, you should have:

- [x] Connected to the EKS cluster
- [x] AWS Load Balancer Controller installed
- [x] CodeCommit repository created
- [x] Local Git repository cloned and initialized
- [x] Ready to install ArgoCD
