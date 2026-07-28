# 🔄 Module 4: Sync Policies & Drift Management

<p align="center">
  <img src="https://img.shields.io/badge/Duration-45%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Intermediate-yellow" />
  <img src="https://img.shields.io/badge/Module-4%20of%208-orange" />
</p>

---

## 🎯 Objective

Understand how ArgoCD reacts when Git or the cluster changes — and how to configure it to handle drift automatically.

---

## 4.1 Why Drift Happens

In a running system, the cluster can diverge from Git in two ways:

### Git Drift

Someone pushes a change to Git, but the cluster hasn't been updated yet.

```
Git:     replicas: 5 (new commit)
Cluster: replicas: 3 (old state)

Result: OutOfSync
```

### Cluster Drift

Someone changes the cluster directly (kubectl, console, another controller), but Git still has the old value.

```
Git:     replicas: 3
Cluster: replicas: 10 (someone ran kubectl scale)

Result: OutOfSync
```

### Real-world examples

- A developer runs `kubectl edit` to hotfix a production issue
- An HPA scales replicas beyond what's declared in Git
- Someone manually deletes a resource
- A CI pipeline applies a manifest directly without going through Git

In all these cases, the cluster no longer matches Git. ArgoCD detects this — but what it **does** about it depends on the **sync policy**.

---

## 4.2 Manual Sync Policy

This is what we've been using so far.

```yaml
syncPolicy: {}
```

**Behavior:**
- ArgoCD detects drift ✅
- ArgoCD syncs automatically ❌
- You must click Sync or run `argocd app sync`

**When to use it:**
- Environments where you want human approval before changes are applied
- When you need to review what's about to be deployed before it goes live

---

## 4.3 Automated Sync Policy

Let's remove the human from the loop.

```yaml
syncPolicy:
  automated: {}
```

**Behavior:** ArgoCD automatically syncs whenever it detects OutOfSync. No human intervention needed.

### Let's enable automated sync:

Update your Application manifest:

```bash
cd ~/environment

cat <<EOF > application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bookstore
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io/foreground
spec:
  project: default
  source:
    repoURL: $REPO_URL
    targetRevision: HEAD
    path: apps/bookstore
  destination:
    server: https://kubernetes.default.svc
    namespace: bookstore
  syncPolicy:
    automated: {}
EOF

kubectl apply -f application.yaml
```

Now push a change:

```bash
cd ~/environment/argocd-workshop

# Change the version text
sed -i 's/v1.0/v2.0/' apps/bookstore/deployment.yaml
git add .
git commit -m "Bump to v2.0"
git push
```

Watch ArgoCD detect and sync automatically:

```bash
kubectl get apps -n argocd -w
```

You'll see the status transition from **Synced → OutOfSync → Synced** without you doing anything.

> [!TIP]
> In non-production environments (dev, staging), automated sync is the standard. It gives developers fast feedback.

---

## 4.4 Prune

### The Problem

What happens when you **remove** a manifest from Git?

Let's find out. First, create a ConfigMap:

```bash
cd ~/environment/argocd-workshop

cat <<'EOF' > apps/bookstore/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: bookstore-config
data:
  greeting: "Hello from ArgoCD"
EOF

git add .
git commit -m "Add configmap"
git push
```

Wait for sync, then verify:

```bash
kubectl get configmap bookstore-config -n bookstore
```

ConfigMap exists. ✅

Now **remove it from Git:**

```bash
rm apps/bookstore/configmap.yaml
git add .
git commit -m "Remove configmap"
git push
```

Wait for reconciliation, then check:

```bash
kubectl get configmap bookstore-config -n bookstore
```

**It's still there!** 😮

ArgoCD synced the removal — but without `prune` enabled, it refuses to delete resources from the cluster. The ConfigMap is now **orphaned** — it exists in the cluster but no one manages it.

### The Fix: Enable Prune

Update your `application.yaml`:

```yaml
  syncPolicy:
    automated:
      prune: true
```

```bash
kubectl apply -f ~/environment/application.yaml
```

Now check again:

```bash
kubectl get configmap bookstore-config -n bookstore
```

```
Error from server (NotFound): configmaps "bookstore-config" not found
```

ArgoCD deleted it because it's no longer in Git.

> [!IMPORTANT]
> **Prune = if it's not in Git, it shouldn't be in the cluster.** This keeps your cluster clean and prevents orphaned resources from accumulating.

---

## 4.5 Self-Heal

### The Problem

What happens when someone makes a change **directly in the cluster**?

Let's find out:

```bash
# Scale the deployment manually (bypassing Git)
kubectl scale deployment bookstore -n bookstore --replicas=10
```

Check ArgoCD:

```bash
argocd app get bookstore
```

It shows **OutOfSync** — ArgoCD detected the drift. But it didn't fix it. The cluster still has 10 replicas.

Without self-heal, the manual change persists. ArgoCD sees the drift but doesn't revert it.

### The Fix: Enable Self-Heal

Update your `application.yaml`:

```yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```bash
kubectl apply -f ~/environment/application.yaml
```

Now ArgoCD immediately reverts the replicas back to what Git says.

```bash
kubectl get deploy bookstore -n bookstore
```

Back to **3 replicas**. ✅

### Let's see it in real-time:

```bash
# Scale again
kubectl scale deployment bookstore -n bookstore --replicas=10

# Watch the revert happen (within seconds)
kubectl get deploy bookstore -n bookstore -w
```

You'll see replicas jump to **10**, then revert back to **3** almost instantly.

> [!NOTE]
> Self-heal uses Kubernetes **watch events** — it doesn't wait for the 3-minute timer. The revert happens almost instantly.

### Try deleting a resource:

```bash
# Delete the service manually
kubectl delete svc bookstore -n bookstore

# Watch it come back
kubectl get svc -n bookstore -w
```

ArgoCD recreates it within seconds because Git says it should exist.

---

## 📊 Summary

| Policy | Git changes | Manual cluster changes | Removed from Git |
|--------|-------------|----------------------|-----------------|
| Manual (`syncPolicy: {}`) | Detects, waits | Detects, waits | Detects, waits |
| `automated: {}` | Auto-syncs | Detects, waits | Detects, waits |
| `automated + prune` | Auto-syncs | Detects, waits | Auto-deletes |
| `automated + selfHeal` | Auto-syncs | Auto-reverts | Detects, waits |
| `automated + prune + selfHeal` | Auto-syncs | Auto-reverts | Auto-deletes |

### The full config:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

This means:
- Push to Git → auto-deploys ✅
- Remove from Git → auto-deletes ✅
- Someone edits the cluster directly → auto-reverts ✅

---

## 🔑 Key Takeaways

| Concept | One-liner |
|---------|-----------|
| Manual Sync | Human approval required before every deploy |
| Automated Sync | ArgoCD deploys whenever Git changes |
| Prune | Resources removed from Git get deleted from cluster |
| Self-Heal | Manual cluster changes get reverted to match Git |

---

> **What's Next:** We can now deploy automatically, but what about controlling the **order** of deployment? In the next module, we'll use Sync Waves to sequence resources and Hooks to run jobs before/after deployment.

---

## ❓ Refresher Questions

<details>
<summary>Q1: You push a new image tag to Git. With automated sync enabled but prune disabled, what happens?</summary>

<br>

ArgoCD detects the change and automatically syncs — the new image is deployed. Prune only matters when resources are **removed** from Git, not when they're updated.

</details>

<details>
<summary>Q2: A developer runs <code>kubectl delete configmap bookstore-config</code>. Self-heal is enabled. What happens?</summary>

<br>

If the ConfigMap exists in Git, ArgoCD recreates it within seconds. If it doesn't exist in Git, nothing happens — ArgoCD only restores resources that are declared in Git.

</details>

<details>
<summary>Q3: You remove a file from Git. Automated sync is enabled but prune is disabled. What happens to the resource in the cluster?</summary>

<br>

Nothing. The resource stays in the cluster as an **orphaned resource**. ArgoCD shows it as "OutOfSync" but won't delete it without prune enabled.

</details>

<details>
<summary>Q4: What's the difference between self-heal and automated sync?</summary>

<br>

**Automated sync** reacts when **Git changes** (desired state changes). **Self-heal** reacts when the **cluster changes** (live state changes). They handle opposite directions of drift.

</details>