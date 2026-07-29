# 🔒 Module 7: Security & Multi-Tenancy

<p align="center">
  <img src="https://img.shields.io/badge/Duration-60%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Advanced-red" />
  <img src="https://img.shields.io/badge/Module-7%20of%208-orange" />
</p>

---

## 🎯 Objective

Learn how ArgoCD enforces security boundaries — who can do what, and what applications are allowed to deploy where.

---

## 7.1 The Three Layers of Security

ArgoCD security works in layers. Each layer answers a different question:

```
Layer 1: Authentication     → "Who are you?"
Layer 2: Authorization      → "What can you do?"
Layer 3: AppProjects        → "What can your Application deploy, from where, and to where?"
```

Important distinction:
- **Layers 1-2** control the **user** (what actions they can perform)
- **Layer 3** controls the **application** (allowed repos, destinations, resource types)

A user might have permission to create an Application, but the AppProject might reject the deployment. These are separate checks.

---

## 7.2 Authentication — Local Users

Authentication answers: **"Who are you?"**

ArgoCD supports multiple identity providers (OIDC, LDAP, Dex). For this workshop, we'll use **local users** — managed directly by ArgoCD.

### The built-in admin user

When you installed ArgoCD, it created one user: `admin`. This is stored as a Secret (password) but the user itself is built-in — not defined anywhere in configuration.

### Create additional users

Users are defined in the `argocd-cm` ConfigMap:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "accounts.bookstore-dev": "apiKey, login",
    "accounts.shipping-dev": "apiKey, login"
  }
}'
```

The format is `accounts.<username>: <capabilities>`:

| Capability | Meaning |
|------------|---------|
| `login` | Can log in via UI/CLI (human users) |
| `apiKey` | Can generate API tokens (automation/CI) |

### Verify accounts exist

```bash
argocd account list
```

You should see `admin`, `bookstore-dev`, and `shipping-dev`.

### Set passwords

```bash
# Make sure you're logged in as admin
ADMIN_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
argocd login $ARGOCD_SERVER --username admin --password $ADMIN_PASS --insecure

# Set passwords for new users
argocd account update-password --account bookstore-dev --current-password $ADMIN_PASS --new-password Bookstore123
argocd account update-password --account shipping-dev --current-password $ADMIN_PASS --new-password Shipping123
```

### Test login

```bash
argocd login $ARGOCD_SERVER --username bookstore-dev --password Bookstore123 --insecure
```

> [!NOTE]
> At this point, the user has an **identity** but no meaningful permissions. Authentication only establishes WHO you are — not what you can do.

---

## 7.3 Authorization (RBAC) — Global Policies

Authorization answers: **"What can this user do?"**

RBAC is configured in the `argocd-rbac-cm` ConfigMap. Let's look at it:

```bash
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

You'll notice the `data` section is empty — no policies are defined yet.

### Built-in Roles

ArgoCD comes with two pre-defined roles:

| Role | Access |
|------|--------|
| `role:readonly` | Read-only access to all resources |
| `role:admin` | Unrestricted access to all resources |

### Key fields in `argocd-rbac-cm`

| Field | Purpose |
|-------|---------|
| `policy.csv` | Where you define custom RBAC policies (who can do what) |
| `policy.default` | The default role assigned to any authenticated user |

When a user logs in and there's no explicit policy for them, they receive whatever role is set in `policy.default`.

Since our ConfigMap is empty:
- `policy.default` is not set → ArgoCD defaults to `role:readonly`
- This means **every authenticated user can currently view everything**

### The `policy.default` options

| Value | Effect |
|-------|--------|
| Not set (absent) | Defaults to `role:readonly` — users can view everything |
| `role:readonly` | Same as above — explicit |
| `""` (empty string) | Zero permissions — users can't see or do anything |

### Start with zero permissions

Let's set `policy.default` to empty so we can build up permissions from scratch:

```bash
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
  "data": {
    "policy.default": "",
    "policy.csv": ""
  }
}'
```

Now **no one** except `admin` has any access.

### Test — bookstore-dev should now have no access:

Remember, we currently have these Applications running from earlier modules:

```
argocd-workshop/
└── apps/
    ├── bookstore/
    ├── inventory/
    └── shipping/
```

Login as `bookstore-dev` and try:

```bash
argocd login $ARGOCD_SERVER --username bookstore-dev --password Bookstore123 --insecure

# Try to list applications
argocd app list

# Try to create an application
argocd app create test --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook --dest-server https://kubernetes.default.svc --dest-namespace default
```

**What you'll see:**

- `app list` returns an **empty list** (not an error) — the apps exist, but `bookstore-dev` can't see them because there's no `get` permission
- `app create` returns **permission denied** — this is a targeted action that gets explicitly denied

> [!NOTE]
> `list` operations work as a **filter** — ArgoCD shows you only what you're allowed to see. No permission = empty list. Targeted actions like `create`, `sync`, `delete` return explicit permission denied errors.

### The error message explained:

```
permission denied: applications, create, default/test, sub: bookstore-dev
```

| Part | Meaning |
|------|---------|
| `applications` | The resource type |
| `create` | The action attempted |
| `default/test` | The project/app-name (`default` is the AppProject, `test` is the app) |
| `sub: bookstore-dev` | The subject (who tried) |

### RBAC Policy Syntax

Two types of rules:

```csv
# Permission rule: grant an action to a subject
p, <subject>, <resource>, <action>, <object>, <effect>

# Group rule: assign a user to a role
g, <user>, <role>
```

| Part | Meaning | Examples |
|------|---------|---------|
| subject | Who | `bookstore-dev`, `role:developers` |
| resource | What type | `applications`, `projects`, `clusters`, `logs`, `exec` |
| action | What operation | `get`, `create`, `update`, `delete`, `sync`, `*` |
| object | Which specific one | `bookstore/*`, `default/my-app`, `*/*` |
| effect | Allow or deny | `allow`, `deny` |

### Give both users full access (for now)

We haven't introduced AppProjects yet, so let's give both users all permissions on the `default` project (which is what all our current apps use):

```bash
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
  "data": {
    "policy.default": "",
    "policy.csv": "p, role:developer, applications, *, default/*, allow\ng, bookstore-dev, role:developer\ng, shipping-dev, role:developer\n"
  }
}'
```

### Test — the create that failed earlier should now work:

```bash
argocd login $ARGOCD_SERVER --username bookstore-dev --password Bookstore123 --insecure

# This failed earlier — now it should work
argocd app create test --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook --dest-server https://kubernetes.default.svc --dest-namespace default

# Can view apps now?
argocd app list
```

Both work ✅

### Test — try to delete

```bash
# Try to delete the app we just created
argocd app delete test --yes
```

This works too — because we gave `*` (all actions) on `default/*`.

### Clean up

```bash
# Login as admin and delete the test app
ADMIN_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
argocd login $ARGOCD_SERVER --username admin --password $ADMIN_PASS --insecure
argocd app delete test --yes 2>/dev/null
```

> [!NOTE]
> Right now both users have full access to `default/*`. That's not ideal — anyone can deploy anything anywhere. In the next section, we'll introduce AppProjects to create proper boundaries per team.

---

## 7.4 AppProjects — Deployment Boundaries

So far, every Application we've created has used `project: default`. But what IS a project?

### What is an AppProject?

An AppProject provides a **logical grouping** of Applications. It's especially useful when ArgoCD is shared by multiple teams.

An AppProject can:

- **Restrict source repositories** — which Git repos an Application can pull from
- **Restrict destinations** — which clusters and namespaces an Application can deploy to
- **Restrict resource types** — what kinds of objects can be deployed (e.g., block CRDs, DaemonSets, ClusterRoles)
- **Define project roles** — RBAC within the project (what we covered in the previous section)

### The Default Project

Every Application belongs to exactly one project. If you don't specify one, it belongs to `default`.

The `default` project is created automatically and permits **everything**:
- Any source repo ✅
- Any cluster ✅
- Any namespace ✅
- Any resource type ✅

That's fine for learning — but in production, you'd never let every team deploy anywhere.

### Create a restricted project

Let's create a project for the bookstore team that only allows deployments to a specific namespace from a specific repo:

```bash
argocd proj create bookstore \
  -d https://kubernetes.default.svc,bookstore \
  -s $REPO_URL
```

This says:
- **Destination:** only `bookstore` namespace on the local cluster
- **Source:** only our workshop repo

View the project:

```bash
argocd proj get bookstore
```

Or as YAML:

```bash
kubectl get appproject bookstore -n argocd -o yaml
```

You'll see the spec:

```yaml
spec:
  destinations:
    - namespace: bookstore
      server: https://kubernetes.default.svc
  sourceRepos:
    - <your-repo-url>
```

### Create the shipping project

```bash
argocd proj create shipping \
  -d https://kubernetes.default.svc,shipping \
  -s $REPO_URL
```

### Now we have boundaries

| Project | Allowed namespace | Allowed repo |
|---------|-------------------|--------------|
| `default` | Any | Any |
| `bookstore` | `bookstore` only | Workshop repo only |
| `shipping` | `shipping` only | Workshop repo only |

### Test — Create apps in the correct project

```bash
# Login as admin to create apps (bookstore-dev doesn't have create yet on the new project)
ADMIN_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
argocd login $ARGOCD_SERVER --username admin --password $ADMIN_PASS --insecure

# Create app in bookstore project (should work)
argocd app create bookstore-app \
  --repo $REPO_URL \
  --path apps/bookstore \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace bookstore \
  --project bookstore \
  --sync-policy automated \
  --sync-option CreateNamespace=true
```

### Test — Violate AppProject policy

```bash
# Try deploying to a namespace the project doesn't allow
argocd app create bookstore-hack \
  --repo $REPO_URL \
  --path apps/bookstore \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace kube-system \
  --project bookstore
```

This will create the Application CR (user RBAC allows it), but ArgoCD will **reject the sync**:

```
application destination namespace "kube-system" does not match any of the allowed destinations in project "bookstore"
```

> [!IMPORTANT]
> The Application object gets created (Kubernetes doesn't know about AppProject policies). But the Application Controller **validates** it against the AppProject before reconciling — and blocks the deployment.

### Test — Cross-project boundary (RBAC)

Now that we have proper projects, let's scope each team's RBAC to their own project:

```bash
ADMIN_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
argocd login $ARGOCD_SERVER --username admin --password $ADMIN_PASS --insecure

kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '{
  "data": {
    "policy.default": "",
    "policy.csv": "p, role:bookstore-team, applications, *, bookstore/*, allow\np, role:bookstore-team, applications, get, */*, allow\np, role:shipping-team, applications, *, shipping/*, allow\np, role:shipping-team, applications, get, */*, allow\ng, bookstore-dev, role:bookstore-team\ng, shipping-dev, role:shipping-team\n"
  }
}'
```

This says:
- `bookstore-team` can do **everything** on apps in the `bookstore` project, and **view** all apps
- `shipping-team` can do **everything** on apps in the `shipping` project, and **view** all apps

Now test:

```bash
# Login as bookstore-dev
argocd login $ARGOCD_SERVER --username bookstore-dev --password Bookstore123 --insecure

# Try to create in the shipping project (should FAIL — RBAC blocks it)
argocd app create shipping-hack \
  --repo $REPO_URL \
  --path apps/bookstore \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace shipping \
  --project shipping
```

This fails at the **RBAC layer** — `bookstore-dev` only has `*` permission on `bookstore/*`, not `shipping/*`.

---

## 7.5 Project Roles — Delegated Access

So far, all permissions are managed by the platform team (global `argocd-rbac-cm`). But what if the bookstore team wants to give someone **delete** access within their project — without asking the platform team?

**Project Roles** let team owners manage permissions within their own project.

### Add a project role

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: bookstore
  namespace: argocd
spec:
  sourceRepos:
    - '*'
  destinations:
    - namespace: bookstore
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  roles:
    - name: team-admin
      description: "Can delete apps in bookstore project"
      policies:
        - p, proj:bookstore:team-admin, applications, delete, bookstore/*, allow
      groups:
        - bookstore-dev
EOF
```

The format `proj:bookstore:team-admin` means: "the `team-admin` role inside the `bookstore` project."

The `groups` field assigns `bookstore-dev` to this role.

### Test — delete should now work

```bash
argocd login $ARGOCD_SERVER --username bookstore-dev --password Bookstore123 --insecure

# Delete the app (should work — project role grants it)
argocd app delete bookstore-app --yes
```

But `bookstore-dev` still **cannot** delete apps in the `shipping` project — the project role only applies within `bookstore`.

### How Global + Project RBAC work together

```
Permission check = Global RBAC   OR   Project RBAC

Either one saying "allow" is enough.
deny always wins (regardless of where it's defined).
```

Project RBAC is **additive** — it adds permissions the global policy doesn't have. It cannot restrict what global RBAC already allows.

---

## 7.6 The Two Permission Checks (Summary)

Every request goes through two independent checks:

```
┌─────────────────────────────────┐
│ CHECK 1: User Permissions       │
│ (RBAC — global + project roles) │
│                                 │
│ "Can this USER perform this     │
│  action in ArgoCD?"             │
└─────────────────────────────────┘
              │
              ▼ (if allowed)
┌─────────────────────────────────┐
│ CHECK 2: Application Policy     │
│ (AppProject)                    │
│                                 │
│ "Can this APPLICATION deploy    │
│  from this repo, to this        │
│  namespace, on this cluster?"   │
└─────────────────────────────────┘
              │
              ▼ (if allowed)
         Deployment proceeds
```

Both must pass. Either one can block.

---

## 🔑 Key Takeaways

| Layer | What it controls | Where configured |
|-------|-----------------|-----------------|
| Authentication | Who is the user? | `argocd-cm` (local users) or SSO |
| Global RBAC | What can the user do? | `argocd-rbac-cm` ConfigMap |
| Project RBAC | Delegated per-project permissions | AppProject `spec.roles` |
| AppProject | What can the Application deploy? | AppProject `spec` (sourceRepos, destinations, etc.) |

---

## ❓ Questions

<details>
<summary>Q1: A user has global permission to create Applications. They create one targeting kube-system. What happens?</summary>

<br>

The Application CR is created (RBAC allows it). But the Application Controller validates it against the AppProject — if the project doesn't allow `kube-system` as a destination, the sync is rejected. The Application exists but never deploys.

</details>

<details>
<summary>Q2: The bookstore team adds shipping-dev to their project role. Can shipping-dev now access bookstore apps?</summary>

<br>

Yes — project RBAC is additive. Unless there's a global `deny` rule for `shipping-dev` on `bookstore/*`, the project role grants access.

</details>

<details>
<summary>Q3: What's the difference between policy.default: "" and policy.default: role:readonly?</summary>

<br>

`""` = zero permissions for unmatched users (can't even view apps).
`role:readonly` = unmatched users can view everything but can't modify anything.

</details>

<details>
<summary>Q4: Where would you use a deny rule?</summary>

<br>

When you need a hard boundary that no one can override — not even project owners. For example: "shipping-dev can NEVER touch bookstore apps, regardless of what the bookstore team adds to their project roles."

```csv
p, shipping-dev, applications, *, bookstore/*, deny
```

</details>
