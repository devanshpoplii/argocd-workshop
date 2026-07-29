# ☁️ Module 8: EKS Managed ArgoCD Capability

<p align="center">
  <img src="https://img.shields.io/badge/Duration-60%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Advanced-red" />
  <img src="https://img.shields.io/badge/Module-8%20of%208-orange" />
</p>

---

## 🎯 Objective

Experience the fully managed ArgoCD capability on EKS and understand how it compares to self-managed ArgoCD.

---

## 8.1 What is the EKS Managed ArgoCD Capability?

With EKS Capabilities, Argo CD is **fully managed by AWS**, eliminating the need to install, maintain, and scale Argo CD controllers and their dependencies on your clusters.

The Argo CD software runs in the **AWS control plane**, not on your worker nodes. This means your worker nodes don't need direct access to Git repositories or Helm registries — the capability handles source access from the AWS account.

It supports the same Kubernetes APIs and CRDs you already know — Applications, ApplicationSets, AppProjects, sync policies, Helm, Kustomize, and plain YAML manifests.

> **Reference:** [Continuous Deployment with Argo CD - Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html)

---

## 8.2 Create the Infrastructure

Download and run the setup script:

```bash
curl -O https://raw.githubusercontent.com/devanshpoplii/argocd-workshop/main/08-managed-capability/setup-infra.sh
chmod +x setup-infra.sh
./setup-infra.sh
```

**What the script does:**

- Creates a new VPC with public and private subnets + NAT gateway
- Creates `hub-cluster` (where the managed ArgoCD capability will be enabled)
- Creates `workload-cluster` (where applications will be deployed)
- Both clusters have managed node groups

> [!NOTE]
> This takes ~20 minutes. ☕

---

## 8.3 Enable AWS IAM Identity Center

Previously, we used a **local admin user** to log into ArgoCD. The managed capability **does not support local user or account creation**. Instead, it uses **AWS IAM Identity Center** (formerly AWS SSO) for authentication.

### Enable Identity Center (CLI):

```bash
aws sso-admin create-instance --region $AWS_REGION
```

Verify it's active:

```bash
aws sso-admin list-instances --region $AWS_REGION
```

### Disable MFA (Console):

1. Go to **AWS IAM Identity Center** in the console
2. Go to **Settings** → **Authentication**
3. Under **Multi-factor authentication** → click **Configure** → set to **Disabled**

### Create a User (Console):

1. In Identity Center, go to **Users** → **Add user**
2. Fill in:
   - Username: `argocd-admin`
   - Email: (use any valid email)
   - First name: `ArgoCD`
   - Last name: `Admin`
3. Select **Generate a one-time password** (instead of sending email)
4. Click **Next** → **Add user**
5. **Save the one-time password** — you'll use it to log into ArgoCD

---

## 8.4 Create the ArgoCD Capability

1. Go to **Amazon EKS** → Select `hub-cluster` → **Capabilities** tab
2. Click **Create capability**
3. Configuration:
   - Capability type: **Argo CD**
   - Capability name: `argocd`
   - Namespace: `argocd`
   - IAM role: Click **Create Argo CD role** (creates a role with `AWSSecretsManagerClientReadOnlyAccess` pre-selected for Secrets Manager integration)
   - Identity Center instance: Select the instance you created in Step 8.3
4. **RBAC Role Mapping:**
   - Map your Identity Center user (`argocd-admin`) to the **Admin** role

> [!TIP]
> ### Comparison: RBAC Configuration
>
> | Self-Managed | Managed Capability |
> |---|---|
> | Define roles manually in `argocd-rbac-cm` | 3 roles provided by default (admin, editor, viewer) |
> | Map users via Casbin policy syntax | Map Identity Center users/groups in the console |
> | Manage `policy.csv` ConfigMap | No ConfigMap management |

5. Click **Create**

Wait for the capability status to become **ACTIVE** (~2-3 minutes).

---

## 8.5 Access the ArgoCD UI

Once the capability is active, find the **ArgoCD Server URL** in the EKS Console under the Capabilities tab.

Open it in your browser.

> [!TIP]
> ### Comparison: Exposing ArgoCD UI
>
> | Self-Managed | Managed Capability |
> |---|---|
> | Create a LoadBalancer service ($$$) | UI hosted by AWS — no LB needed |
> | Configure security groups | No networking setup |
> | Manage TLS certificates | AWS manages certificates |
> | Pay for NLB/ALB hourly | No additional cost for exposure |

---

## 8.6 Where Are the Pods?

Run this on your hub-cluster:

```bash
aws eks update-kubeconfig --name hub-cluster
kubectl get pods -n argocd
kubectl get svc -n argocd
```

You'll see **no ArgoCD controller pods** and **no services**. The controllers run in the AWS control plane — completely invisible to your cluster.

> [!TIP]
> ### Comparison: Installation & Operations
>
> | Self-Managed | Managed Capability |
> |---|---|
> | `kubectl apply` installs 5+ controller pods | No pods on your nodes |
> | Pods consume node CPU/memory | Zero node resource consumption |
> | You manage upgrades and patching | AWS handles automatically |
> | You configure HA (Redis, replicas) | Built-in HA and fault tolerance |
> | You troubleshoot CrashLoopBackOff | No in-cluster troubleshooting |

> **From AWS docs:** *"EKS Capabilities run in EKS and off of your clusters, freeing up node resources. Capabilities do not consume CPU or memory on your worker nodes, scale automatically, and have minimal impact on cluster capacity planning."*

---

## 8.7 SSO Login

You'll see an SSO login option on the ArgoCD UI. Log in with the Identity Center user you created (`argocd-admin`) using the one-time password you saved earlier.

> [!TIP]
> ### Comparison: Authentication
>
> | Self-Managed | Managed Capability |
> |---|---|
> | Local users in `argocd-cm` ConfigMap | No local users supported |
> | SSO requires Dex/OIDC setup | Native Identity Center integration |
> | Manual token management | AWS manages sessions |
> | Configure callback URLs, client secrets | Zero SSO configuration |

---

## 8.8 Register the Local Cluster

Open the **Settings → Clusters** section in the ArgoCD UI. Notice that the local cluster (where ArgoCD is deployed) is **not added by default** — unlike self-managed where `in-cluster` exists automatically.

Register it using a Kubernetes Secret:

```bash
CLUSTER_ARN=$(aws eks describe-cluster --name hub-cluster --query "cluster.arn" --output text)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: local-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: local-cluster
  server: $CLUSTER_ARN
  project: default
EOF
```

Check the ArgoCD UI — the cluster should now appear.

> [!NOTE]
> The managed capability uses **EKS cluster ARNs** as the server identifier — not `https://kubernetes.default.svc`. This is how it integrates natively with EKS Access Entries.

---

## 8.9 Repository Configuration

### CodeCommit — Direct Integration

For AWS CodeCommit repositories, the managed capability provides **direct integration**. Simply add `codecommit:GitPull` permission to the capability role and use the repo URL directly — no Repository Secret needed.

### Private Repositories (GitHub, Bitbucket, etc.)

For private repos outside AWS, you need credentials. But instead of storing them directly in a Kubernetes Secret (where they're base64 visible), the managed capability integrates with **AWS Secrets Manager**.

**Create a secret in Secrets Manager:**

```bash
aws secretsmanager create-secret \
  --name argocd/workshop-repo \
  --description "GitHub credentials for ArgoCD" \
  --secret-string '{"username":"devanshpoplii","password":"<your-github-pat>"}'
```

**Reference it in a Kubernetes Secret by ARN:**

```bash
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id argocd/workshop-repo --query "ARN" --output text)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: workshop-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/devanshpoplii/argocd-workshop
  secretArn: $SECRET_ARN
  project: default
EOF
```

Notice: **no password in the Kubernetes Secret**. Only an ARN reference. The capability fetches the actual credentials from Secrets Manager at runtime.

> [!TIP]
> ### Comparison: Credential Management
>
> | Self-Managed | Managed Capability |
> |---|---|
> | Credentials stored in K8s Secret (base64 visible) | Only ARN reference in K8s Secret |
> | Manual credential rotation | Rotate in Secrets Manager, ArgoCD picks up automatically |
> | CSI Secrets Store Driver needed for Secrets Manager integration | Native integration — no drivers needed |
> | Credentials visible via `kubectl get secret -o yaml` | Credentials never stored in cluster |

---

*More sections coming: Remote cluster deployment, Application creation, and full comparison summary...*

## 8.10 Register the Remote Cluster

### What we had to do previously (self-managed):

1. ✅ Ensure **network communication** between clusters — same VPC required SG rules; different VPCs required VPC Peering or Transit Gateway
2. ✅ Create an **IAM role** with the correct trust policy
3. ✅ Install **Pod Identity add-on** on the ArgoCD cluster
4. ✅ Create **pod-identity-associations** for ArgoCD service accounts
5. ✅ Add the IAM role to the remote cluster's **Access Entry**
6. ✅ **Restart ArgoCD pods** to pick up Pod Identity credentials
7. ✅ Create a **cluster Secret** with `awsAuthConfig`

For cross-account: all of the above PLUS cross-account IAM role assumption + trust policies between accounts.

### What we do now (managed capability):

Add the ArgoCD capability role to the remote cluster's Access Entry. That's it.

```bash
# Get the capability role ARN
CAPABILITY_ROLE_ARN=$(aws iam get-role --role-name AmazonEKSCapabilityArgoCDRole --query "Role.Arn" --output text)

# Get remote cluster name and region
REMOTE_CLUSTER="workload-cluster"
REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null)}

# Add access entry
aws eks create-access-entry \
  --region $REGION \
  --cluster-name $REMOTE_CLUSTER \
  --principal-arn $CAPABILITY_ROLE_ARN \
  --type STANDARD

# Associate admin policy
aws eks associate-access-policy \
  --region $REGION \
  --cluster-name $REMOTE_CLUSTER \
  --principal-arn $CAPABILITY_ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### Register the cluster in ArgoCD

```bash
REMOTE_CLUSTER_ARN=$(aws eks describe-cluster --name workload-cluster --query "cluster.arn" --output text)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: workload-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: workload-cluster
  server: $REMOTE_CLUSTER_ARN
  project: default
EOF
```

Navigate to the ArgoCD UI → **Settings → Clusters**. You should see `workload-cluster` listed.

> [!IMPORTANT]
> **No network configuration was required.** The workload cluster has a **private-only** API endpoint — yet ArgoCD can reach it. AWS manages connectivity between the capability and private remote clusters automatically.

### Cross-account?

The same steps apply for cross-account setup. No additional IAM role creation or trust policy configuration is required — EKS Access Entries handle cross-account access. Simply register the private cluster using its ARN.

> [!TIP]
> ### Comparison: Multi-Cluster Registration
>
> | Self-Managed | Managed Capability |
> |---|---|
> | Long-lived bearer tokens (security risk) | No tokens — IAM-based |
> | Pod Identity add-on installation required | No add-on needed |
> | IAM role + trust policy creation | Just add capability role to Access Entry |
> | SG rules required (same VPC) | No networking config |
> | VPC Peering/Transit Gateway (cross-VPC) | No networking config |
> | Cross-account IAM role assumption setup | Just add ARN to Access Entry |
> | Restart ArgoCD pods after config | No restarts |
> | Private clusters need network path | **Transparent access to private clusters** |

---

## 8.11 Deploy an Application to the Remote Cluster

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    name: workload-cluster
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

Check the ArgoCD UI — the guestbook application should appear and sync to the workload cluster.

> [!NOTE]
> **Try this with your neighbor!** Ask the person sitting next to you for their workload cluster ARN. Add their capability role to your cluster's Access Entry — and they can deploy to your cluster. Cross-account GitOps in 2 commands.

---

## 8.12 Full Comparison: Self-Managed vs Managed Capability

> Reference: [EKS Capabilities considerations](https://docs.aws.amazon.com/eks/latest/userguide/capabilities-considerations.html)

### Deployment & Management

| | Self-Managed | Managed Capability |
|--|---|---|
| **Installation** | `kubectl apply` or Helm — install 5+ controllers | One-click in EKS Console or `aws eks create-capability` |
| **Configuration** | Manage ConfigMaps (`argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm`) | Configured via capability API |
| **CRD management** | You install and upgrade CRDs | AWS manages CRDs automatically |
| **Customization** | Full control over all settings | Opinionated defaults — less knobs, better defaults |

### Operations & Maintenance

| | Self-Managed | Managed Capability |
|--|---|---|
| **Upgrades** | Track releases, test, redeploy | AWS handles automatically |
| **Security patches** | Monitor CVEs, rebuild images | AWS patches automatically |
| **High availability** | Configure Redis HA, multiple replicas, PDBs | Built-in HA and fault tolerance |
| **Scaling** | Manual sharding configuration | Scales automatically |
| **Monitoring** | Set up your own alerting | Managed observability |
| **Troubleshooting** | Debug CrashLoopBackOff, OOMKills, leader election | No in-cluster troubleshooting |

### Resource Consumption

| | Self-Managed | Managed Capability |
|--|---|---|
| **Node resources** | 5+ pods consuming CPU/memory | Zero — runs in AWS control plane |
| **Cluster resources** | Consumes cluster IPs, service accounts | Minimal cluster footprint |
| **Capacity planning** | Must plan for ArgoCD workloads | No capacity planning needed |

### Authentication & RBAC

| | Self-Managed | Managed Capability |
|--|---|---|
| **Local users** | Supported (ConfigMap) | Not supported |
| **SSO** | Requires Dex/OIDC configuration | Native Identity Center integration |
| **RBAC roles** | Define manually in `argocd-rbac-cm` | 3 built-in roles (admin, editor, viewer) |
| **Role mapping** | Casbin policy syntax | Map Identity Center groups in console |

### Multi-Cluster

| | Self-Managed | Managed Capability |
|--|---|---|
| **Authentication** | Bearer tokens or Pod Identity/IRSA | Capability role + Access Entry |
| **Private clusters** | Requires network path (SG, VPC Peering) | Transparent access — no networking setup |
| **Cross-account** | Cross-account IAM roles + trust policies | Just add ARN to Access Entry |
| **Cluster registration** | Complex Secret with `awsAuthConfig` | Simple Secret with cluster ARN |

### Repository Access

| | Self-Managed | Managed Capability |
|--|---|---|
| **CodeCommit** | IAM user + HTTPS Git credentials | Direct integration via capability role |
| **Private repos** | Credentials in K8s Secret (base64 visible) | Secrets Manager ARN reference |
| **Credential rotation** | Manual | Rotate in Secrets Manager, auto-picked up |

### Cost

| | Self-Managed | Managed Capability |
|--|---|---|
| **Direct AWS cost** | None (but you pay for node compute) | Hourly capability fee |
| **Node compute** | 5+ pods on your nodes | Zero |
| **Load Balancer** | Required for UI exposure | Not needed |
| **Engineer time** | Patching, upgrading, troubleshooting | Minimal ops overhead |
| **Total cost of ownership** | Node compute + LB + engineer time | Predictable hourly pricing |

---

## 💰 Pricing

EKS Capabilities have an hourly cost per capability resource. For current pricing:

👉 [Amazon EKS Pricing](https://aws.amazon.com/eks/pricing/)

---

## 🔑 Key Takeaways

The managed capability eliminates operational overhead at every layer:

- **No installation** — one click
- **No pods on your nodes** — runs in AWS control plane
- **No SSO setup** — native Identity Center
- **No networking for multi-cluster** — transparent private cluster access
- **No credential management** — Secrets Manager integration
- **No patching or upgrades** — AWS handles it
- **Same ArgoCD APIs** — your manifests work with minimal changes
