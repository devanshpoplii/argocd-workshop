# 🚀 Module 1: ArgoCD Installation

<p align="center">
  <img src="https://img.shields.io/badge/Duration-30%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Beginner-green" />
  <img src="https://img.shields.io/badge/Module-1%20of%207-orange" />
</p>

---

## 🎯 Objective

Install ArgoCD on your EKS cluster, expose the UI, and verify access.

---

## 1.1 Install ArgoCD

```bash
# Create a dedicated namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
```

Verify all pods are running:

```bash
kubectl get pods -n argocd
```

> [!IMPORTANT]
> All pods should show `Running` and `1/1` Ready before proceeding.

---

## 1.2 Expose the ArgoCD UI

By default, the ArgoCD server is only accessible inside the cluster (`ClusterIP`). Let's expose it externally using a Network Load Balancer.

```bash
# Patch the service to use an internet-facing NLB
kubectl patch svc argocd-server -n argocd -p '{
  "metadata": {
    "annotations": {
      "service.beta.kubernetes.io/aws-load-balancer-scheme": "internet-facing",
      "service.beta.kubernetes.io/aws-load-balancer-type": "external",
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip"
    }
  },
  "spec": {
    "type": "LoadBalancer"
  }
}'
```

Get the URL:

```bash
echo "ArgoCD URL: $(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

> [!NOTE]
> It may take a minute or two for the load balancer to become reachable. If the browser shows a timeout, wait and retry.

> [!WARNING]
> You'll see a certificate warning — this is expected. ArgoCD uses a self-signed certificate by default. Click **Advanced** → **Proceed** to continue.

---

## 1.3 Get the Admin Password

```bash
# Decode the initial admin password
echo "Password: $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"
```

Login to the UI:

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | *(output from above)* |

---

## 1.4 Login via CLI

```bash
# Store the ArgoCD server hostname
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Login to ArgoCD via CLI
argocd login $ARGOCD_SERVER --username admin --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d) --insecure
```

> [!TIP]
> You should see: `'admin:login' logged in successfully`

---

## 1.5 Explore the UI

Take a moment to look around:

- 📦 **Applications** — Currently empty.
- 🔗 **Settings → Repositories** — No repos connected yet.
- 📁 **Settings → Projects** — A `default` project exists.
- 🖥️ **Settings → Clusters** — Shows `in-cluster`.

---

<details>
<summary>🔧 Troubleshooting</summary>

| Problem | Solution |
|---------|----------|
| Pods not starting | Check node resources: `kubectl describe nodes` |
| LB hostname not appearing | Wait 2 min, check LB controller logs |
| Can't access UI | Verify security group allows inbound on port 80/443 |
| CLI login fails | Ensure `--insecure` flag is used (self-signed cert) |

</details>

---

## ✅ End State

At the end of Module 1, you should have:

- [x] ArgoCD installed and all pods Running
- [x] UI accessible via browser (NLB URL)
- [x] Logged in as admin (UI and CLI)
- [x] Ready to deploy your first application
