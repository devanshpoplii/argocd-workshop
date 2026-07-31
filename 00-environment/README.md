# 🏗️ Module 0: Environment Setup

<p align="center">
  <img src="https://img.shields.io/badge/Duration-30%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Beginner-green" />
  <img src="https://img.shields.io/badge/Module-0%20of%207-orange" />
</p>

---

## 🎯 Objective

In this module, we'll set up our working environment:

- Verify that our EKS cluster is running
- Create a **Git repository** (CodeCommit) where we'll store all our Kubernetes manifest files throughout the workshop
- Install the **AWS Load Balancer Controller** so we can expose services externally

---

## 0.1 Grant Permissions to IDE

Your IDE role needs additional permissions for this workshop. Run this in your IDE terminal:

```bash
curl -O https://raw.githubusercontent.com/devanshpoplii/argocd-workshop/main/00-environment/grant-permissions.sh
chmod +x grant-permissions.sh
./grant-permissions.sh
```

The script will output a command. **Copy that command and run it in CloudShell** (not in the IDE).

> [!IMPORTANT]
> Open CloudShell from the AWS Console (top-right icon). Paste and run the command there, then come back to the IDE.

---

## 0.2 Verify the Environment

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

## 0.3 Bootstrap the Environment

We need two things before we can start working with ArgoCD:

1. **AWS Load Balancer Controller** — this allows Kubernetes Services to create Network Load Balancers (NLBs) on AWS, which we'll use to access ArgoCD from the browser.
2. **A CodeCommit Git repository** — this is where we'll store all our Kubernetes manifest files. ArgoCD will watch this repository and deploy whatever we put in it.

Rather than setting these up manually, we'll use a bootstrap script that does both.

**Download and run the script:**

```bash
curl -O https://raw.githubusercontent.com/devanshpoplii/argocd-workshop/main/00-environment/bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

> [!IMPORTANT]
> Wait for the script to complete before proceeding. It will print your Git credentials at the end — note them down, we'll need them later when connecting ArgoCD to our repository.

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

---

<p align="center">
  <b>Next up → <a href="../01-argocd-installation/">Module 1: Install ArgoCD</a></b>
</p>
