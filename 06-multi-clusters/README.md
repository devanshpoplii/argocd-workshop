# 🌐 Module 6: Multi-Cluster GitOps

<p align="center">
  <img src="https://img.shields.io/badge/Duration-60%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Advanced-red" />
  <img src="https://img.shields.io/badge/Module-6%20of%208-orange" />
</p>

---

## 🎯 Objective

Deploy applications across multiple EKS clusters from a single ArgoCD instance using production-grade authentication.

---

## 6.1 Create the Target Clusters

```bash
curl -O https://raw.githubusercontent.com/devanshpoplii/argocd-immersion-day/main/6-multi-cluster/create-clusters.sh
chmod +x create-clusters.sh
./create-clusters.sh
```

> [!NOTE]
> This creates `dev-cluster` and `prod-cluster` with private nodes in the same VPC. Takes ~15 minutes. ☕

After completion, update your kubeconfig with the new clusters:

```bash
aws eks update-kubeconfig --name dev-cluster
aws eks update-kubeconfig --name prod-cluster

# Switch back to ArgoCD cluster
aws eks update-kubeconfig --name eks-workshop
```

---

## 6.2 Register a Cluster with ArgoCD

ArgoCD runs inside `eks-workshop`. It has no idea other clusters exist. To deploy to a remote cluster, we need to **register** it — give ArgoCD the credentials to talk to that cluster's API server.

```bash
# Get the context name for dev-cluster
DEV_CONTEXT=$(kubectl config get-contexts -o name | grep dev-cluster)

# Register with ArgoCD
argocd cluster add $DEV_CONTEXT --name dev-cluster
```

> [!WARNING]
> This will likely **fail** with a timeout:
> ```
> dial tcp <IP>:443: i/o timeout
> ```

### Why did it fail?

Both clusters are in the **same VPC**. When ArgoCD resolves the dev-cluster's API server hostname, DNS returns the **private IP** (because private endpoint is enabled). The traffic goes through the VPC internally — but the target cluster's **security group** blocks it.

```
ArgoCD Pod → resolves dev-cluster API → gets private IP
          → sends request on port 443
          → hits dev-cluster's security group
          → NO inbound rule for port 443 from ArgoCD's SG
          → TIMEOUT
```

---

## 6.3 Fix Network Connectivity

Allow the ArgoCD cluster's security group to reach the target clusters on port 443:

```bash
# Get ArgoCD cluster's security group
ARGOCD_SG=$(aws eks describe-cluster --name eks-workshop --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Get dev-cluster's security group
DEV_SG=$(aws eks describe-cluster --name dev-cluster --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Get prod-cluster's security group
PROD_SG=$(aws eks describe-cluster --name prod-cluster --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

# Allow ArgoCD cluster to reach dev-cluster API server
aws ec2 authorize-security-group-ingress \
  --group-id $DEV_SG \
  --protocol tcp \
  --port 443 \
  --source-group $ARGOCD_SG

# Allow ArgoCD cluster to reach prod-cluster API server
aws ec2 authorize-security-group-ingress \
  --group-id $PROD_SG \
  --protocol tcp \
  --port 443 \
  --source-group $ARGOCD_SG
```

---

## 6.4 Register Clusters (Retry)

```bash
DEV_CONTEXT=$(kubectl config get-contexts -o name | grep dev-cluster)
PROD_CONTEXT=$(kubectl config get-contexts -o name | grep prod-cluster)

# Register with friendly names
argocd cluster add $DEV_CONTEXT --name dev-cluster -y
argocd cluster add $PROD_CONTEXT --name prod-cluster -y
```

Verify:

```bash
argocd cluster list
```

You should see `dev-cluster` and `prod-cluster` alongside `in-cluster`.

### What did `argocd cluster add` just do?

On each target cluster, it created:

- A **ServiceAccount** (`argocd-manager`) in `kube-system`
- A **ClusterRole** + **ClusterRoleBinding** (cluster-admin)
- A **long-lived bearer token** for that ServiceAccount

Then it stored that token as a **Secret** in the ArgoCD cluster's `argocd` namespace.

### Inspect the Secret:

```bash
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
```

Pick one and look at its contents:

```bash
kubectl get secret -n argocd $(kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o jsonpath='{.items[0].metadata.name}') -o yaml
```

You'll see `config`, `name`, and `server` — all base64 encoded. Decode the config:

```bash
kubectl get secret -n argocd $(kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o jsonpath='{.items[0].metadata.name}') -o jsonpath='{.data.config}' | base64 -d | jq .
```

Notice the **bearerToken** — this is a static, long-lived token that never expires.

---

## 6.5 Deploy to a Remote Cluster

Now that the cluster is registered, we can target it with an Application:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bookstore-dev
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
    name: dev-cluster
    namespace: bookstore
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

`destination.name: dev-cluster` — this matches the `--name` we used during registration.

Verify:

```bash
argocd app get bookstore-dev
```

The bookstore is now running on `dev-cluster` — deployed and managed from `eks-workshop`.

---

## 6.6 The Problem with Long-Lived Tokens

The bearer token stored in the Secret:

- ❌ **Never expires** (unless manually rotated)
- ❌ **If leaked**, gives cluster-admin access forever
- ❌ **No automatic rotation**
- ❌ **Bypasses CloudTrail** (it's a K8s SA token, not IAM)

EKS uses IAM for authentication. We should use **short-lived IAM credentials** instead of static tokens.

---

## 6.7 Switch to Pod Identity (Production Approach)

### Remove the long-lived token approach:

```bash
argocd cluster rm dev-cluster -y
argocd cluster rm prod-cluster -y
```

This removes the Secrets from ArgoCD (and cleans up the SA + ClusterRoleBinding on the remote clusters).

---

### Step 1: Install Pod Identity Agent

Pod Identity injects AWS credentials into pods based on their ServiceAccount. First, install the agent on the ArgoCD cluster:

```bash
aws eks create-addon \
  --cluster-name eks-workshop \
  --addon-name eks-pod-identity-agent

# Wait for it to be active
aws eks wait addon-active --cluster-name eks-workshop --addon-name eks-pod-identity-agent
```

---

### Step 2: Create an IAM Role for ArgoCD

This role has **no AWS permissions** — it's only used to authenticate to EKS. The actual cluster permissions come from EKS Access Entries.

```bash
# Create the trust policy (allows Pod Identity to assume this role)
cat <<'EOF' > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name argocd-multi-cluster-role \
  --assume-role-policy-document file://trust-policy.json

rm trust-policy.json
```

> [!IMPORTANT]
> No permission policies are attached. This role's only purpose is to **identify** the ArgoCD pods to the target clusters.

---

### Step 3: Create Access Entries on Target Clusters

This tells each target cluster: "When this IAM role authenticates, give it cluster-admin access."

```bash
ROLE_ARN=$(aws iam get-role --role-name argocd-multi-cluster-role --query "Role.Arn" --output text)

# Grant access on dev-cluster
aws eks create-access-entry \
  --cluster-name dev-cluster \
  --principal-arn $ROLE_ARN \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name dev-cluster \
  --principal-arn $ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

# Grant access on prod-cluster
aws eks create-access-entry \
  --cluster-name prod-cluster \
  --principal-arn $ROLE_ARN \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name prod-cluster \
  --principal-arn $ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

---

### Step 4: Create Pod Identity Associations

This tells EKS: "When pods running with these ServiceAccounts need credentials, give them the argocd-multi-cluster-role."

```bash
ROLE_ARN=$(aws iam get-role --role-name argocd-multi-cluster-role --query "Role.Arn" --output text)

# Application Controller (performs sync)
aws eks create-pod-identity-association \
  --cluster-name eks-workshop \
  --namespace argocd \
  --service-account argocd-application-controller \
  --role-arn $ROLE_ARN

# ArgoCD Server (UI/CLI operations)
aws eks create-pod-identity-association \
  --cluster-name eks-workshop \
  --namespace argocd \
  --service-account argocd-server \
  --role-arn $ROLE_ARN

# ApplicationSet Controller (generates Applications)
aws eks create-pod-identity-association \
  --cluster-name eks-workshop \
  --namespace argocd \
  --service-account argocd-applicationset-controller \
  --role-arn $ROLE_ARN
```

---

### Step 5: Restart ArgoCD Pods

Pod Identity injects credentials at pod startup. Existing pods don't pick up new associations:

```bash
kubectl rollout restart statefulset/argocd-application-controller -n argocd
kubectl rollout restart deploy/argocd-server -n argocd
kubectl rollout restart deploy/argocd-applicationset-controller -n argocd

# Wait for pods to be ready
kubectl get pods -n argocd
```

Verify credentials are injected:

```bash
kubectl exec -it argocd-application-controller-0 -n argocd -- env | grep AWS
```

You should see `AWS_CONTAINER_CREDENTIALS_FULL_URI` — proof that Pod Identity is working.

---

### Step 6: Register Clusters Declaratively

Now we register clusters using a Secret — no bearer token, just `awsAuthConfig`:

```bash
DEV_SERVER=$(aws eks describe-cluster --name dev-cluster --query "cluster.endpoint" --output text)
DEV_CA=$(aws eks describe-cluster --name dev-cluster --query "cluster.certificateAuthority.data" --output text)

PROD_SERVER=$(aws eks describe-cluster --name prod-cluster --query "cluster.endpoint" --output text)
PROD_CA=$(aws eks describe-cluster --name prod-cluster --query "cluster.certificateAuthority.data" --output text)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: dev-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: dev
stringData:
  name: dev-cluster
  server: $DEV_SERVER
  config: |
    {
      "awsAuthConfig": {
        "clusterName": "dev-cluster"
      },
      "tlsClientConfig": {
        "insecure": false,
        "caData": "$DEV_CA"
      }
    }
---
apiVersion: v1
kind: Secret
metadata:
  name: prod-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: production
stringData:
  name: prod-cluster
  server: $PROD_SERVER
  config: |
    {
      "awsAuthConfig": {
        "clusterName": "prod-cluster"
      },
      "tlsClientConfig": {
        "insecure": false,
        "caData": "$PROD_CA"
      }
    }
EOF
```

Notice:
- **No `bearerToken`** — ArgoCD uses its Pod Identity credentials
- **`awsAuthConfig.clusterName`** — tells ArgoCD which cluster to get a token for
- **`environment` labels** — we'll use these with generators

Verify:

```bash
argocd cluster list
```

---

## 6.8 Cluster Generator

Deploy the **same app to all registered clusters** automatically:

```bash
kubectl delete application bookstore-dev -n argocd 2>/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: bookstore-all-clusters
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: 'bookstore-{{name}}'
    spec:
      project: default
      source:
        repoURL: $REPO_URL
        targetRevision: HEAD
        path: apps/bookstore
      destination:
        name: '{{name}}'
        namespace: bookstore
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF
```

The Cluster Generator scans all Secrets with `argocd.argoproj.io/secret-type: cluster` and produces a dataset:

| name | server |
|------|--------|
| dev-cluster | https://... |
| prod-cluster | https://... |

Each row renders the template → one Application per cluster.

```bash
kubectl get applications -n argocd
```

`bookstore-dev-cluster` and `bookstore-prod-cluster` — both generated from a single ApplicationSet.

> [!NOTE]
> `in-cluster` is excluded because it has no Secret — the Cluster Generator only discovers clusters represented by labeled Secrets.

---

## 6.9 Matrix Generator

Deploy **every app** to **every cluster** — Cartesian Product:

```bash
kubectl delete applicationset bookstore-all-clusters -n argocd

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: all-apps-all-clusters
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: $REPO_URL
              revision: HEAD
              directories:
                - path: apps/*
          - clusters:
              selector:
                matchLabels:
                  argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{path.basename}}-{{name}}'
    spec:
      project: default
      source:
        repoURL: $REPO_URL
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        name: '{{name}}'
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF
```

The Matrix Generator combines two datasets:

```
Git Generator:              Cluster Generator:
+------------------+       +------------------+
| path.basename    |   ×   | name             |
+------------------+       +------------------+
| bookstore        |       | dev-cluster      |
| shipping         |       | prod-cluster     |
+------------------+       +------------------+

Result: 4 Applications (2 apps × 2 clusters)
```

```bash
kubectl get applications -n argocd
```

Every app on every cluster — from a single ApplicationSet.

---

## 🔑 Key Takeaways

| Concept | One-liner |
|---------|-----------|
| `argocd cluster add` | Quick but uses long-lived static tokens |
| Pod Identity | Production approach — short-lived, auto-rotating IAM credentials |
| Access Entries | How EKS maps IAM roles to cluster permissions |
| Security Groups | Clusters in same VPC still need explicit rules for API communication |
| Cluster Generator | Deploys same app to all labeled clusters |
| Matrix Generator | Every app × every cluster (Cartesian Product) |

---

## ❓ Questions

<details>
<summary>Q1: Why doesn't the declarative Secret have a bearerToken?</summary>

<br>

Because Pod Identity already provides AWS credentials to the ArgoCD pod. With `awsAuthConfig.clusterName`, ArgoCD uses those credentials to call `aws eks get-token` which returns a short-lived STS token (~15 min). No static token needed.

</details>

<details>
<summary>Q2: What happens if you register a third cluster with the matching label?</summary>

<br>

The Matrix Generator discovers it and automatically creates Applications for every app folder on that cluster — without changing the ApplicationSet YAML.

</details>

<details>
<summary>Q3: Why do we restart ArgoCD pods after creating pod-identity-associations?</summary>

<br>

Pod Identity injects credentials at **pod startup**. Existing running pods don't pick up new associations automatically. Restarting forces new pods to start with the injected credentials.

</details>
