<p align="center">
  <img src="https://img.shields.io/badge/Methodology-GitOps-blueviolet?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Tool-ArgoCD-orange?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" />
</p>

<h1 align="center">🔄 Why Did We Need GitOps?</h1>

---

## The Starting Point

Let's start with a typical Kubernetes deployment.

```
👤 Developer
    │
    ▼
📂 Git Repository
    │
    ▼
⚙️  CI/CD Pipeline
    │   • Builds the application
    │   • Runs automated tests
    │   • Builds a container image
    │   • Deploys to Kubernetes
    ▼
☸️  Kubernetes Cluster
```

The deployment completes. The pipeline finishes. Everything appears to be working.

**So… what's the problem?**

At first glance, nothing.

---

## ❌ Problem 1 — Configuration Drift

The application was deployed with:

```yaml
replicas: 2    # Healthy ✅
```

Later that night, traffic increases. An engineer quickly scales:

```bash
kubectl scale deployment nginx --replicas=5
```

Now we have **two versions of reality**:

```
┌─────────────────────────┐          ┌─────────────────────────┐
│                         │          │                         │
│        📂 Git           │          │     ☸️ Cluster          │
│                         │          │                         │
│     replicas: 2         │    ≠     │     replicas: 5         │
│                         │          │                         │
└─────────────────────────┘          └─────────────────────────┘
```

Which one is correct? Nobody knows.

This is **configuration drift** — the live cluster has silently drifted away from what Git says it should be.

---

## ❌ Problem 2 — Untracked Production Changes

A few days later, another engineer fixes an urgent production issue by modifying the Deployment directly:

```bash
kubectl edit deployment nginx
```

They update the container image. Production starts working again. Everyone is happy.

Except… **Git was never updated.**

A month later, someone investigates:

> *"Why are we running 5 replicas?"* — Nobody remembers.
>
> *"Who updated the container image?"* — Nobody knows.
>
> *"Show me every production change from last month."* — Security team

Where do you look? Git history? CI/CD logs? Kubernetes audit logs? CloudTrail? Slack messages?

**There is no single place that tells the complete story.**

---

## ❌ Problem 3 — Rollbacks Become Risky

Today's deployment introduces a bug. You want to roll back.

But questions immediately arise:

- Which version was *actually* running before?
- Did someone manually change production since?
- Is Git still accurate?
- If we redeploy from Git, will we overwrite an important hotfix?

Because Git and the cluster are no longer identical, **rollbacks become guesswork.**

---

## ❌ Problem 4 — Rebuilding the Environment

The cluster is accidentally deleted. You provision a new one.

Can you recreate everything exactly as it was?

> ❓ Which Helm charts were installed?
>
> ❓ Which values files were used?
>
> ❓ Which ConfigMaps were manually updated?
>
> ❓ Which Secrets were modified?
>
> ❓ Which production fixes were applied directly?

Some of this exists in Git. Some exists only in the old cluster. Some exists **only in people's memories.**

---

## 🎯 The Root Cause

None of these problems are caused by Kubernetes.
None are caused by your CI/CD pipeline.

The real issue is simple:

> **Git ≠ Kubernetes Cluster**

Once a deployment finishes, changes keep happening directly inside the cluster — and nobody tracks them back to Git. Over time, engineers stop trusting Git because it no longer reflects what's actually running.

---

## 💡 What We Needed

Instead of asking *"What is running in the cluster?"* — we wanted to confidently say:

> **"Whatever is in Git is exactly what's running."**

We needed a system that could:

- ✅ Continuously compare Git with the Kubernetes cluster
- ✅ Detect drift the moment it happens
- ✅ Alert us — or automatically fix it
- ✅ Make Git the single source of truth again

This operational model is called **GitOps**.

---

## 🚀 What is GitOps?

**GitOps is simple:**

You store what your cluster *should* look like in Git. A controller running inside the cluster watches Git, and whenever something doesn't match — it fixes it.

```
                    ┌────────────────────┐
                    │   📂 Git           │
                    │   (Desired State)  │
                    └────────┬───────────┘
                             │
                      Watches & Pulls
                             │
                             ▼
                    ┌────────────────────┐
                    │   🔄 Controller    │
                    │   (inside cluster) │
                    └────────┬───────────┘
                             │
                      Compares & Syncs
                             │
                             ▼
                    ┌────────────────────┐
                    │   ☸️ Cluster       │
                    │   (Actual State)   │
                    └────────────────────┘

              If Git ≠ Cluster → Controller fixes it.
              Continuously. Automatically.
```

> [!TIP]
> Unlike traditional CI/CD which deploys once and stops, a GitOps controller **never stops watching**. It runs 24/7 inside the cluster.

---

### What does this give us?

| Before (CI/CD only) | After (GitOps) |
|---------------------|-----------------|
| Deploy once, then forget | Continuously verify and reconcile |
| Drift goes unnoticed for weeks | Drift detected in seconds |
| Rollback = "which version was it again?" | Rollback = `git revert` + `git push` |
| Rebuild from memory + tribal knowledge | Rebuild = point controller to Git repo |
| Audit = search 5 different systems | Audit = `git log` |
| Trust erodes over time | Git is always the truth |

---

## 🔶 Where Does ArgoCD Fit?

**GitOps** is the methodology.

**ArgoCD** is a tool that implements GitOps for Kubernetes.

It runs as a set of controllers inside your cluster and continuously:

```
  👁️  Watches your Git repository for changes
  🔍  Compares the desired state (Git) with the actual state (cluster)
  🟡  Detects differences → marks application as OutOfSync
  🔄  Synchronizes the cluster back to match Git
```

It never stops. It continuously reconciles.

---

### 🤔 Wait — does this mean ArgoCD replaces our CI/CD pipelines?

<details>
<summary>Think about it, then click to reveal</summary>

<br>

**No.** ArgoCD handles the **delivery** side. Your CI pipeline still does the **build** side.

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  👤 Developer pushes code                                            │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────────────────────────────┐                         │
│  │         CI Pipeline                     │                         │
│  │                                         │                         │
│  │   ✅ Build application                  │                         │
│  │   ✅ Run tests                          │                         │
│  │   ✅ Build container image              │                         │
│  │   ✅ Push image to registry             │                         │
│  │   ✅ Update manifest in Git             │  ← CI stops here        │
│  │                                         │                         │
│  └─────────────────────────────────────────┘                         │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────────────────────────────┐                         │
│  │         ArgoCD (GitOps)                 │                         │
│  │                                         │                         │
│  │   ✅ Detect new manifest in Git         │                         │
│  │   ✅ Deploy to Kubernetes               │                         │
│  │   ✅ Monitor continuously               │                         │
│  │   ✅ Detect & fix drift                 │  ← ArgoCD never stops   │
│  │                                         │                         │
│  └─────────────────────────────────────────┘                         │
│       │                                                              │
│       ▼                                                              │
│  ☸️  Kubernetes Cluster                                               │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**CI builds it. ArgoCD deploys and watches it. They work together.**

</details>

---

## What We'll Do Today

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   🏗️ Install ArgoCD        📦 Deploy an app        🔨 Break things     │
│      on EKS            →      through Git       →     on purpose        │
│                                                                         │
│                                                         │               │
│                                                         ▼               │
│                                                                         │
│   🌐 Go multi-cluster   ←   🔐 Add access        ←  🔄 Watch ArgoCD   │
│                                 controls               fix it           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

```
  One App, One Cluster  →  Many Apps, Many Clusters
```

---

<p align="center">
  <b>Let's begin → <a href="./00-environment/">Module 0: Environment Setup</a></b>
</p>
