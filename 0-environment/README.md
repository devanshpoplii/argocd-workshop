# Module 1: ArgoCD Installation

## Objective

Install ArgoCD on your EKS cluster, expose the UI, and verify access.

## Outcome

By the end of this module, you will have:

- ✔ ArgoCD installed in the `argocd` namespace
- ✔ All ArgoCD components running
- ✔ ArgoCD UI accessible via browser
- ✔ ArgoCD CLI installed and logged in

---

## 1.1 Install ArgoCD

ArgoCD runs as a set of Kubernetes components inside your cluster. It needs its own namespace.

```bash
# Create a dedicated namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
```

This installs several components. Let's verify they're running:

```bash
# Wait for all pods to be ready
kubectl get pods -n argocd -w
```

You should see the following components:

| Component | What it does |
|-----------|-------------|
| `argocd-server` | API server — serves the UI and CLI requests |
| `argocd-repo-server` | Clones Git repos and generates manifests |
| `argocd-application-controller` | Watches applications, detects drift, performs sync |
| `argocd-redis` | In-memory cache for performance |
| `argocd-applicationset-controller` | Generates Applications from templates |
| `argocd-dex-server` | Handles SSO/authentication |

All pods should show `Running` and `1/1` Ready before proceeding.

---

## 1.2 Expose the ArgoCD UI

By default, the ArgoCD server is only accessible inside the cluster (`ClusterIP`). Let's expose it externally using a Load Balancer.

```bash
# Change the service type to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Wait ~2 minutes for AWS to provision the load balancer, then get the URL:

```bash
# Get the load balancer hostname
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open this URL in your browser with `https://` prefix.

> ⚠️ You'll see a certificate warning — this is expected. The default ArgoCD installation uses a self-signed certificate. Click "Advanced" → "Proceed" to continue.

---

## 1.3 Get the Admin Password

ArgoCD creates an initial admin password stored as a Kubernetes Secret. The password is base64-encoded.

```bash
# Get and decode the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
echo
```

Now login to the UI:

- **Username:** `admin`
- **Password:** *(output from above)*

---

## 1.4 Install the ArgoCD CLI

The CLI lets you manage ArgoCD from the terminal — useful for scripting and faster operations.

```bash
# Download the CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Verify installation
argocd version --client
```

Login via CLI:

```bash
# Get the ArgoCD server hostname
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Login (--insecure because of self-signed cert)
argocd login $ARGOCD_SERVER --username admin --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d) --insecure
```

You should see: `'admin:login' logged in successfully`

---

## 1.5 Explore the UI

Take a moment to look around the ArgoCD UI:

- **Applications** — Currently empty. We'll create our first one in the next module.
- **Settings → Repositories** — No repos connected yet.
- **Settings → Projects** — You'll see a `default` project.
- **Settings → Clusters** — Shows `in-cluster` (the cluster ArgoCD is running on).

---

## End State

At the end of Module 1, you should have:

- ✔ ArgoCD installed and all pods Running
- ✔ UI accessible via browser (Load Balancer URL)
- ✔ Logged in as admin (UI and CLI)
- ✔ Ready to deploy your first application
