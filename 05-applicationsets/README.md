# 🔁 Module 5: ApplicationSets

<p align="center">
  <img src="https://img.shields.io/badge/Duration-60%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Intermediate-yellow" />
  <img src="https://img.shields.io/badge/Module-5%20of%208-orange" />
</p>

---

## 🎯 Objective

Learn how to manage multiple Applications from a single resource using ApplicationSets and Generators.

---

## 5.1 Why ApplicationSets?

So far, we've created one Application manually. But what happens when you have 10, 50, or 200 services?

```
apps/
├── bookstore/
├── inventory/
├── payments/
├── shipping/
├── notifications/
└── ...
```

Would you create 200 Application manifests by hand? Each nearly identical except for the name and path?

**ApplicationSets** solve this. Instead of writing one Application per service, you write **one template** and let ArgoCD generate the Applications automatically.

---

## 5.2 Application vs ApplicationSet

| | Application | ApplicationSet |
|--|-------------|----------------|
| **Creates** | One deployment | Multiple Applications |
| **Managed by** | Application Controller | ApplicationSet Controller |
| **Input** | Static YAML | Generator + Template |

An ApplicationSet has two parts:

- **Generator** — produces a list of values ("what apps should exist?")
- **Template** — defines what each generated Application looks like

---

## 5.3 Prepare the Repository

Let's add a second application to our repo so we have something for the generator to discover:

```bash
cd ~/environment/argocd-workshop

mkdir -p apps/inventory
```

```bash
cat <<'EOF' > apps/inventory/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory
  template:
    metadata:
      labels:
        app: inventory
    spec:
      containers:
      - name: inventory
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
```

```bash
cat <<'EOF' > apps/inventory/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: inventory
spec:
  selector:
    app: inventory
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

```bash
git add .
git commit -m "Add inventory service"
git push
```

Your repo now looks like:

```
argocd-workshop/
└── apps/
    ├── bookstore/
    │   ├── deployment.yaml
    │   └── service.yaml
    └── inventory/
        ├── deployment.yaml
        └── service.yaml
```

---

## 5.4 List Generator

The simplest generator — you explicitly list what Applications should exist.

First, let's delete the manually created bookstore Application (the ApplicationSet will manage it now):

```bash
kubectl delete application bookstore -n argocd
```

Now create the ApplicationSet:

```bash
cd ~/environment

cat <<EOF > applicationset-list.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workshop-apps-list
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - app: bookstore
          - app: inventory
  template:
    metadata:
      name: '{{app}}'
    spec:
      project: default
      source:
        repoURL: $REPO_URL
        targetRevision: HEAD
        path: 'apps/{{app}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{app}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF

kubectl apply -f applicationset-list.yaml
```

### How it works internally:

The generator produces a **dataset** — think of it as a table:

| app |
|-----|
| bookstore |
| inventory |

The ApplicationSet Controller then loops through this dataset and **renders the template once per row**:

```
Iteration 1:  app = bookstore
  → name: bookstore
  → path: apps/bookstore
  → namespace: bookstore

Iteration 2:  app = inventory
  → name: inventory
  → path: apps/inventory
  → namespace: inventory
```

Each iteration produces one Application. Two rows = two Applications.

Check what was created:

```bash
kubectl get applications -n argocd
```

You should see **two** Applications: `bookstore` and `inventory` — generated from a single ApplicationSet.

---

## 5.5 The Problem with List Generator

What if a new team adds `apps/shipping/`? Someone must remember to update the ApplicationSet:

```yaml
- app: shipping
```

That's two sources of truth — the repo structure and the list. They will eventually drift apart.

---

## 5.6 Git Generator

The Git Generator **discovers** applications automatically by scanning the repository. The repo structure itself becomes the source of truth.

First, delete the List Generator:

```bash
kubectl delete applicationset workshop-apps-list -n argocd
```

Now create a Git Generator:

The Git Generator scans a directory pattern in your repo. For each matching folder, it provides two variables:

| Variable | What it resolves to | Example |
|----------|---------------------|---------|
| `{{path}}` | Full path of the matched directory | `apps/bookstore` |
| `{{path.basename}}` | Just the folder name (last segment) | `bookstore` |

So if your repo has `apps/bookstore/` and `apps/inventory/`, the generator will iterate twice — once for each — and create an Application for each using these variables in the template.

```bash
cd ~/environment

cat <<EOF > applicationset-git.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workshop-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: $REPO_URL
        revision: HEAD
        directories:
          - path: apps/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: $REPO_URL
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF

kubectl apply -f applicationset-git.yaml
```

Check:

```bash
kubectl get applications -n argocd
```

Same result — `bookstore` and `inventory`. But now, let's see the magic:

### Add a new service without touching the ApplicationSet:

```bash
cd ~/environment/argocd-workshop
mkdir -p apps/shipping

cat <<'EOF' > apps/shipping/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipping
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shipping
  template:
    metadata:
      labels:
        app: shipping
    spec:
      containers:
      - name: shipping
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

cat <<'EOF' > apps/shipping/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: shipping
spec:
  selector:
    app: shipping
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

git add .
git commit -m "Add shipping service"
git push
```

Wait for reconciliation (~3 min), then:

```bash
kubectl get applications -n argocd
```

**Three Applications** now — `bookstore`, `inventory`, and `shipping`. You didn't touch the ApplicationSet. ArgoCD discovered the new folder and generated the Application automatically.

> [!IMPORTANT]
> With the Git Generator, adding a new service = creating a folder. No YAML duplication, no manual Application creation.

### Now remove a service:

```bash
rm -rf apps/inventory
git add .
git commit -m "Remove inventory service"
git push
```

After reconciliation:

```bash
kubectl get applications -n argocd
```

`inventory` is gone — both the Application and its resources were pruned.

---

## 5.7 Understanding the Template Variables

The Git Generator provides these variables for each discovered directory:

| Variable | Example value |
|----------|--------------|
| `{{path}}` | `apps/bookstore` |
| `{{path.basename}}` | `bookstore` |

So when the generator discovers `apps/bookstore`:

```yaml
name: '{{path.basename}}'    →  name: bookstore
path: '{{path}}'             →  path: apps/bookstore
namespace: '{{path.basename}}'  →  namespace: bookstore
```

---

## 5.8 Deletion Behavior

When you delete a folder from Git:

```
Git Generator no longer discovers it
       │
       ▼
ApplicationSet Controller deletes the Application CR
       │
       ▼
Application Controller prunes all resources (Deployment, Service, etc.)
       │
       ▼
Cluster is clean
```

---

## 🔑 Key Takeaways

| Concept | One-liner |
|---------|-----------|
| ApplicationSet | One resource that generates many Applications |
| Generator | Produces the dataset (what apps should exist) |
| Template | Defines what each Application looks like |
| List Generator | Static list you maintain manually |
| Git Generator | Auto-discovers from repo structure |
| Adding a service | Just create a folder — Application appears |
| Removing a service | Delete the folder — Application and resources are pruned |

---

## ❓ Questions

<details>
<summary>Q1: You have 3 folders in apps/. How many Applications does the Git Generator create?</summary>

<br>

3 — one per folder. The generator produces one dataset entry per discovered directory.

</details>

<details>
<summary>Q2: If you modify a file inside apps/bookstore/deployment.yaml (but don't add/remove folders), does the ApplicationSet Controller do anything?</summary>

<br>

No. The ApplicationSet Controller only cares about **which directories exist** (structure changes). Content changes inside an existing folder are handled by the **Application Controller** — it detects the manifest change and syncs.

</details>

<details>
<summary>Q3: What happens if you delete the ApplicationSet itself?</summary>

<br>

All generated Applications are deleted (via ownerReferences garbage collection). Each Application's finalizer triggers resource cleanup. The cluster is left clean.

</details>

---

> **What's Next:** We'll skip Sync Waves & Hooks for now and move to **AppProjects** — controlling what Applications are allowed to deploy and where.
