# 🏛️ Module 3: ArgoCD Architecture

<p align="center">
  <img src="https://img.shields.io/badge/Duration-45%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Beginner-green" />
  <img src="https://img.shields.io/badge/Module-3%20of%208-orange" />
</p>

---

## 🎯 Objective

Now that you've deployed an application, let's understand what happened behind the scenes. By the end of this module, you'll know:

- What each ArgoCD component does
- How a request flows through the system
- The difference between Refresh and Sync
- How they come together in the Reconciliation Loop
- What Sync Status and Health Status mean

---

## 3.1 Core Components

Let's look at what's running inside ArgoCD:

```bash
kubectl get pods -n argocd
```

| Component | What it does |
|-----------|-------------|
| 🌐 **argocd-server** | Entry point — serves the UI, CLI, and API requests |
| 📦 **argocd-repo-server** | Clones Git repos, renders manifests (YAML, Helm, Kustomize) |
| 🧠 **argocd-application-controller** | The brain — watches Applications, detects drift, performs sync |
| ⚡ **argocd-redis** | Shared cache — avoids repeated Git clones and manifest generation |
| 🔄 **argocd-applicationset-controller** | Generates Applications from templates (covered later) |

> [!NOTE]
> The **Repo Server never deploys anything**. It only produces manifests. The **Application Controller** is the only component that talks to your target cluster.

---

## 3.2 End-to-End Request Flow

When you created the bookstore Application and clicked Sync, here's what happened:

```
1. You (UI/CLI)
       │
       ▼
2. API Server received your request
       │
       ▼
3. Stored the Application CR in Kubernetes (etcd)
       │
       ▼
4. Application Controller noticed the new Application
       │
       ▼
5. Controller asked Repo Server: "Give me the manifests for apps/bookstore"
       │
       ▼
6. Repo Server cloned your CodeCommit repo, read the YAML files
       │
       ▼
7. Controller compared those manifests with what's in the cluster
       │
       ▼
8. Controller applied the manifests to the cluster
```

Now that we know the components, let's understand the two core operations that ArgoCD performs continuously: **Refresh** and **Sync**.

---

## 3.3 Refresh

**Refresh** = "Go check Git and tell me if anything changed."

- It does **NOT** change your cluster
- It only updates ArgoCD's knowledge of what Git currently contains

**What happens internally:**

```
1. Controller asks Repo Server: "What's the latest commit?"
2. Repo Server checks Git
3. Controller compares Git manifests vs what's in the cluster
4. Controller updates the Application status (Synced/OutOfSync)
5. NOTHING is deployed or changed in the cluster
```

### Automatic vs Manual Refresh

- **Automatic:** Happens every ~2-3 minutes
- **Manual:** You trigger it yourself

### Replication — see Refresh in action:

Let's make a change in Git and watch ArgoCD detect it **without** deploying anything.

```bash
cd ~/environment/argocd-workshop

# Change replicas from 2 to 3
sed -i 's/replicas: 2/replicas: 3/' apps/bookstore/deployment.yaml

# Push to Git
git add .
git commit -m "Scale to 3 replicas"
git push
```

Trigger a manual refresh:

```bash
argocd app get bookstore --refresh
```

Check the status:

```bash
argocd app get bookstore
```

You should see: **OutOfSync**

But check the cluster:

```bash
kubectl get deploy bookstore -n bookstore
```

Still shows **2 replicas**. The cluster hasn't changed. ArgoCD knows there's a difference, but it hasn't acted.

---

## 3.4 Sync

**Sync** = "Apply all the manifests from Git into the cluster to make them match."

This **changes your cluster**. It takes the desired state from Git and makes it the live state.

**What happens internally:**

```
1. Controller takes the desired manifests (from Git)
2. Applies all of them to the target cluster
3. Waits for resources to become ready
4. Updates Application status
```

### Replication — perform a Sync:

Your app is currently OutOfSync (3 replicas in Git, 2 in cluster). Let's sync:

```bash
argocd app sync bookstore
```

Now verify:

```bash
kubectl get deploy bookstore -n bookstore
```

**3 replicas.** The cluster now matches Git.

### Refresh vs Sync

```
Refresh: "Is there a difference?"     (read-only)
Sync:    "Fix the difference."         (writes to cluster)
```

You always Refresh first, then Sync if needed.

---

## 3.5 Reconciliation Loop

Now that you understand Refresh and Sync, here's how they fit together.

The Application Controller runs a **continuous loop** that combines both:

```
        ┌──────────────────────────┐
        │                          │
        │   1. Refresh             │
        │   2. Diff                │
        │   3. Sync (if enabled)   │
        │                          │
        │   Repeat every ~3 min    │
        │                          │
        └──────────────────────────┘
```

Since we're using **manual sync**, step 3 doesn't happen automatically. ArgoCD detects drift but waits for you to act. In the next module, we'll enable automated sync.

### What triggers reconciliation?

| Trigger | When |
|---------|------|
| **Timer** | Every ~2-3 minutes (automatic) |
| **Webhook** | Git push → ArgoCD notified immediately |
| **Manual Refresh** | You click Refresh in UI or run `argocd app get --refresh` |
| **Application update** | Someone modifies the Application CR |
| **Self-Heal** | Something changes directly in the cluster |

---

## 3.6 Sync Status

After every refresh, ArgoCD answers: **"Does the cluster match Git?"**

| Status | Meaning |
|--------|---------|
| ✅ **Synced** | Cluster matches Git. No action needed. |
| 🟡 **OutOfSync** | There's a difference between Git and the cluster. |
| ❓ **Unknown** | Can't determine state (e.g., Repo Server down, cluster unreachable). |

You already observed both **Synced** and **OutOfSync** during the Refresh and Sync replications above.

---

## 3.7 Health Status

Sync status tells you: **"Does the cluster match Git?"**

Health status tells you: **"Is the application actually working?"**

These are **independent**:

| Sync | Health | What it means |
|------|--------|---------------|
| Synced | Healthy | Everything perfect ✅ |
| Synced | Degraded | Git matches cluster, but pods are crashing 💥 |
| OutOfSync | Healthy | Old version running fine, new version not applied yet |

### Health Statuses

| Status | Meaning |
|--------|---------|
| 💚 **Healthy** | All resources running as expected |
| 🔄 **Progressing** | Rollout in progress (not done yet, not broken) |
| 🔴 **Degraded** | Something is wrong (CrashLoopBackOff, pods failing) |
| ⚠️ **Missing** | Resource declared in Git but doesn't exist in cluster |

### Replication — create a Degraded state:

```bash
cd ~/environment/argocd-workshop

# Push a bad image
sed -i 's/image: nginx:latest/image: nginx:nonexistent-tag/' apps/bookstore/deployment.yaml
git add .
git commit -m "Deploy bad image"
git push

# Sync it
argocd app sync bookstore
```

Check ArgoCD:

```bash
argocd app get bookstore
```

You'll see: **Sync: Synced** but **Health: Degraded**

> [!IMPORTANT]
> **Synced ≠ Healthy.** The cluster perfectly matches Git — but Git has a bad image. This is an important distinction.

**Fix it:**

```bash
sed -i 's/image: nginx:nonexistent-tag/image: nginx:latest/' apps/bookstore/deployment.yaml
git add .
git commit -m "Fix image tag"
git push
argocd app sync bookstore
```

---

## 🔑 Key Takeaways

| Concept | One-liner |
|---------|-----------|
| Refresh | Check Git, update status (no cluster changes) |
| Sync | Apply Git manifests to cluster (cluster changes) |
| Reconciliation Loop | Continuous cycle: refresh → diff → maybe sync |
| Sync Status | Does the cluster match Git? |
| Health Status | Is the application working? |
| They're independent | You can be Synced but Degraded |

---

> **What's Next:** We've been syncing manually every time. In the next module, we'll enable **automated sync** so ArgoCD deploys changes automatically when Git changes — and reverts manual cluster changes back to Git state.

---

<p align="center">
  <b>Next up → <a href="../04-sync-policies/">Module 4: Sync Policies</a></b>
</p>
