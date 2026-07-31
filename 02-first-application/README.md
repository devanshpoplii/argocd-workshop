# 📦 Module 2: Deploy Your First Application

<p align="center">
  <img src="https://img.shields.io/badge/Duration-45%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Beginner-green" />
  <img src="https://img.shields.io/badge/Module-2%20of%208-orange" />
</p>

---

## 🎯 Objective

By the end of this module, you will:

- Understand what an ArgoCD Application is
- Create your first Application resource
- Deploy an application from Git into your cluster
- Observe ArgoCD detecting and reconciling the desired state

---

## 2.1 What is an ArgoCD Application?

We've installed ArgoCD. But how does it know **what** to deploy and **where** to deploy it?

The answer is the **Application** Custom Resource.

An Application is the fundamental object in ArgoCD. It defines:

| Field | Question it answers |
|-------|-------------------|
| **Source** | Where are the manifests stored? (Git repo, path, branch) |
| **Destination** | Which cluster and namespace to deploy to? |
| **Project** | Which security boundary does this app belong to? |
| **Sync Policy** | How should ArgoCD keep the cluster in sync with Git? |

---

## 2.2 Create the Application Manifests

We're going to deploy an **Online Book Store** 📚 — a simple web application that we'll evolve throughout the workshop.

Create the folder structure in your CodeCommit repository:

```bash
cd ~/environment/argocd-workshop
mkdir -p apps/bookstore
```

---

### Deployment

```bash
cat <<'EOF' > apps/bookstore/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bookstore
spec:
  replicas: 2
  selector:
    matchLabels:
      app: bookstore
  template:
    metadata:
      labels:
        app: bookstore
    spec:
      containers:
      - name: bookstore
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      initContainers:
      - name: content
        image: busybox
        command:
        - sh
        - -c
        - |
          cat <<HTML > /html/index.html
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <title>Book Store</title>
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; min-height: 100vh; display: flex; align-items: center; justify-content: center; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%); color: #fff; }
              .container { text-align: center; padding: 60px 40px; background: rgba(255,255,255,0.05); border-radius: 20px; backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); max-width: 500px; }
              .icon { font-size: 4rem; margin-bottom: 20px; }
              h1 { font-size: 2.5rem; margin-bottom: 10px; background: linear-gradient(to right, #e94560, #f5a623); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
              .version { display: inline-block; background: #e94560; color: #fff; padding: 4px 12px; border-radius: 20px; font-size: 0.85rem; margin: 15px 0; }
              .tagline { color: #a0a0b0; font-size: 1.1rem; margin-top: 15px; }
              .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.1); color: #606080; font-size: 0.8rem; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="icon">&#128218;</div>
              <h1>Online Book Store</h1>
              <span class="version">v1.0</span>
              <p class="tagline">Deployed with ArgoCD GitOps</p>
              <div class="footer">ArgoCD Immersion Day Workshop</div>
            </div>
          </body>
          </html>
          HTML
        volumeMounts:
        - name: html
          mountPath: /html
      volumes:
      - name: html
        emptyDir: {}
EOF
```

---

### Service

```bash
cat <<'EOF' > apps/bookstore/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: bookstore
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
spec:
  selector:
    app: bookstore
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOF
```

---

### Push to Git

```bash
git add .
git commit -m "Add bookstore deployment and service"
git push
```

Your repository now looks like:

```
argocd-workshop/
└── apps/
    └── bookstore/
        ├── deployment.yaml
        └── service.yaml
```

> [!NOTE]
> Our manifests are now in Git. ArgoCD doesn't know about them yet — we need to register the repository and create an Application.

---

## 2.3 Register the Repository with ArgoCD

Since CodeCommit is a private repository, ArgoCD needs credentials to access it.

> [!IMPORTANT]
> Make sure you ran the `export` commands printed by the bootstrap script.

```bash
# Get the repo URL
REPO_URL=$(aws codecommit get-repository --repository-name argocd-workshop --query "repositoryMetadata.cloneUrlHttp" --output text)

# Register with ArgoCD
argocd repo add $REPO_URL --username $CC_USERNAME --password $CC_PASSWORD
```

Verify:

```bash
argocd repo list
```

---

## 2.4 Create the ArgoCD Application

Now we tell ArgoCD about our application. Let's build the Application manifest block by block.

---

### Source

*Where should ArgoCD fetch manifests from?*

```yaml
source:
  repoURL: <your-codecommit-repo-url>
  targetRevision: HEAD
  path: apps/bookstore
```

- `repoURL` — Your CodeCommit repository
- `targetRevision` — Which branch/commit to track (`HEAD` = latest)
- `path` — Folder containing the manifests

---

### Destination

*Where should they be deployed?*

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: bookstore
```

- `server` — The cluster to deploy to (`kubernetes.default.svc` = the local cluster)
- `namespace` — Which namespace to deploy into

---

### Project

```yaml
project: default
```

For now, we'll use the `default` project. Later we'll learn how AppProjects isolate teams and enforce security boundaries.

---

### Sync Policy

```yaml
syncPolicy: {}
```

We're starting with **manual sync**. We want to see the deployment process ourselves before enabling automation.

---

### Full Application Manifest

Let's create this file **outside** the repo directory — it's an ArgoCD configuration, not part of the application source code.

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
  syncPolicy: {}
EOF
```

> [!NOTE]
> `$REPO_URL` was already set when we registered the repository in step 2.3.

Apply it:

```bash
kubectl apply -f application.yaml
```

---

## 2.4 Observe the UI

Open the ArgoCD UI. You should now see the **bookstore** application.

Notice:
- 🟡 **Sync Status:** `OutOfSync`
- ❓ **Health:** `Missing`

*Why OutOfSync?*

ArgoCD has compared Git (which has a Deployment and Service) with the cluster (which has nothing in the `bookstore` namespace). They don't match — so it's out of sync.

*Why Missing?*

The resources declared in Git don't exist in the cluster yet. We haven't synced.

> [!TIP]
> **Sync** means applying the manifests from Git into the cluster. ArgoCD detected the drift, but because we chose manual sync, it's waiting for us to act.

---

## 2.5 Perform a Manual Sync

Let's sync — this tells ArgoCD to make the cluster match Git.

**Option A: UI**

Click **Sync** → **Synchronize**

**Option B: CLI**

```bash
argocd app sync bookstore
```

> [!NOTE]
> The sync will fail because the `bookstore` namespace doesn't exist yet. Let's fix that:

```bash
argocd app set bookstore --sync-option CreateNamespace=true
argocd app sync bookstore
```

---

## 2.6 Watch It Come Alive

After sync, observe in the UI:

- ✅ **Sync Status:** `Synced`
- 💚 **Health:** `Healthy`

The resource tree shows:

```
bookstore (Application)
├── Deployment/bookstore
│   └── ReplicaSet/bookstore-xxxxx
│       ├── Pod/bookstore-xxxxx-abc
│       └── Pod/bookstore-xxxxx-def
└── Service/bookstore
```

---

## 2.8 Verify in the Cluster

```bash
# Check all resources
kubectl get all -n bookstore

# Check pods are running
kubectl get pods -n bookstore

# Get the application URL
echo "Bookstore URL: http://$(kubectl get svc bookstore -n bookstore -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Open the URL in your browser — you should see:

> 📚 **Online Book Store**
>
> Version 1.0
>
> Welcome to the ArgoCD Workshop

> [!NOTE]
> It may take a minute for the NLB to become reachable.

---

## 2.9 Observe Application Status

Back in the UI, notice two key indicators:

| Indicator | What it tells you |
|-----------|------------------|
| **Sync Status** | Does the cluster match Git? |
| **Health Status** | Is the application actually working? |

We'll understand exactly what these statuses mean and how they're computed in Module 3 (Architecture).

---

> **What's Next:** We just created a single YAML file called an Application, and ArgoCD deployed everything into Kubernetes. But what actually happened behind the scenes? That's what we'll explore in the next module.

---

<p align="center">
  <b>Next up → <a href="../03-architecture/">Module 3: ArgoCD Architecture</a></b>
</p>
