# ⬆️ Module 9: EKS Cluster Upgrades

<p align="center">
  <img src="https://img.shields.io/badge/Duration-25%20min-blue" />
  <img src="https://img.shields.io/badge/Difficulty-Intermediate-yellow" />
  <img src="https://img.shields.io/badge/Module-9-orange" />
</p>

---

## 🎯 Objective

In this module, we'll upgrade an EKS cluster from **1.33 → 1.34**, covering:

- The difference between Control Plane and Data Plane
- Pre-upgrade checks and upgrade insights
- Upgrading the control plane
- Upgrading the data plane (managed node group)
- Upgrading EKS managed add-ons

---

## 9.1 Concepts

An EKS cluster has two parts:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   Control Plane (managed by AWS)                                │
│   ┌───────────────────────────────────────────────────────┐     │
│   │  API Server │ etcd │ Scheduler │ Controller Manager   │     │
│   └───────────────────────────────────────────────────────┘     │
│                          │                                      │
│                          │ communicates with                    │
│                          ▼                                      │
│   Data Plane (managed by you)                                   │
│   ┌───────────────────────────────────────────────────────┐     │
│   │  Node 1 (kubelet)  │  Node 2 (kubelet)  │  Node 3    │     │
│   │  Pods              │  Pods              │  Pods       │     │
│   └───────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Key rules:

| Rule | Why |
|------|-----|
| **One minor version at a time** | 1.33 → 1.34 ✅ &nbsp;&nbsp; 1.33 → 1.35 ❌ |
| **Control Plane first, then Data Plane** | Nodes can be behind the CP, but never ahead |
| **CP needs free IPs** | EKS creates new ENIs in your cluster subnets during upgrade |

### Upgrade order:

```
1️⃣  Control Plane (API server, etcd, etc.)
        │
        ▼
2️⃣  Data Plane (managed node group)
        │
        ▼
3️⃣  EKS Add-ons (VPC CNI, CoreDNS, kube-proxy)
        │
        ▼
4️⃣  kubectl client
```

---

## 9.2 Pre-Upgrade Checks

Before upgrading, always:

### Review release notes

Check what changed in the target version — deprecated APIs, behavior changes, new features:

- [EKS Release Notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Kubernetes Changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGES/CHANGELOG-1.34.md)

### Check Upgrade Insights

EKS provides built-in upgrade readiness checks. These detect deprecated APIs, unhealthy clusters, and potential blockers:

```bash
aws eks list-insights \
  --cluster-name eks-workshop \
  --filter kubernetesVersions=1.34
```

```bash
# Get details on a specific insight
aws eks describe-insight \
  --cluster-name eks-workshop \
  --id <insight-id>
```

> [!IMPORTANT]
> If any insight shows `ERROR` or `WARNING`, resolve it before upgrading. Common issues:
> - Deprecated API versions still in use (e.g., `policy/v1beta1` → `policy/v1`)
> - Unhealthy nodes or pods
> - Insufficient IP addresses in cluster subnets

### Check current state

```bash
# Current cluster version
aws eks describe-cluster --name eks-workshop --query "cluster.version" --output text

# Current node versions
kubectl get nodes -o wide

# Current add-on versions
aws eks list-addons --cluster-name eks-workshop --output table
aws eks describe-addon --cluster-name eks-workshop --addon-name vpc-cni --query "addon.addonVersion" --output text
aws eks describe-addon --cluster-name eks-workshop --addon-name coredns --query "addon.addonVersion" --output text
aws eks describe-addon --cluster-name eks-workshop --addon-name kube-proxy --query "addon.addonVersion" --output text
```

---

## 9.3 Upgrade the Control Plane

This upgrades the API server, etcd, scheduler, and controller manager — all managed by AWS.

```bash
aws eks update-cluster-version \
  --name eks-workshop \
  --kubernetes-version 1.34
```

Monitor progress:

```bash
aws eks describe-update \
  --name eks-workshop \
  --update-id <update-id-from-above>
```

Or watch the cluster status:

```bash
watch -n 10 "aws eks describe-cluster --name eks-workshop --query 'cluster.{Version:version,Status:status}' --output table"
```

> [!NOTE]
> The control plane upgrade takes **10–15 minutes**. During this time:
> - The API server remains available (zero downtime)
> - Existing workloads continue running
> - You may see brief API latency spikes
>
> We'll continue explaining the next steps while it completes.

---

## 9.4 Upgrade the Data Plane (Managed Node Group)

After the control plane is on 1.34, the nodes are still running 1.33. We need to upgrade the managed node group so nodes match the control plane.

### Check current node group version

```bash
aws eks describe-nodegroup \
  --cluster-name eks-workshop \
  --nodegroup-name <node-group-name> \
  --query "nodegroup.{Version:version,ReleaseVersion:releaseVersion,Status:status}" \
  --output table
```

### Upgrade the node group

```bash
aws eks update-nodegroup-version \
  --cluster-name eks-workshop \
  --nodegroup-name <node-group-name>
```

> [!NOTE]
> This performs a **rolling update**:
> 1. A new node is launched with the 1.34 AMI
> 2. An old node is cordoned (no new pods scheduled)
> 3. Pods are drained from the old node (moved to new node)
> 4. Old node is terminated
> 5. Repeat until all nodes are on 1.34
>
> This ensures **zero downtime** for your workloads.

### Watch the rolling update

```bash
watch -n 5 "kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1].type"
```

You'll see:
1. New node appears (v1.34.x)
2. Old node goes `SchedulingDisabled`
3. Pods move to new node
4. Old node disappears

> [!TIP]
> If your workloads have **PodDisruptionBudgets (PDBs)**, the rolling update respects them — it won't evict more pods than the PDB allows. This is how you protect availability during upgrades.

---

## 9.5 Upgrade EKS Managed Add-ons

Now we upgrade the add-ons to their latest compatible versions.

### Find compatible versions

```bash
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.34 \
  --query "addons[0].addonVersions[0].addonVersion" --output text

aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.34 \
  --query "addons[0].addonVersions[0].addonVersion" --output text

aws eks describe-addon-versions --addon-name kube-proxy --kubernetes-version 1.34 \
  --query "addons[0].addonVersions[0].addonVersion" --output text
```

### Upgrade each add-on

```bash
# VPC CNI
aws eks update-addon \
  --cluster-name eks-workshop \
  --addon-name vpc-cni \
  --resolve-conflicts PRESERVE

# CoreDNS
aws eks update-addon \
  --cluster-name eks-workshop \
  --addon-name coredns \
  --resolve-conflicts PRESERVE

# kube-proxy
aws eks update-addon \
  --cluster-name eks-workshop \
  --addon-name kube-proxy \
  --resolve-conflicts PRESERVE
```

> [!TIP]
> `--resolve-conflicts PRESERVE` keeps any custom configuration you've applied to the add-on. Use `OVERWRITE` if you want to reset to defaults.

### Verify

```bash
aws eks describe-addon --cluster-name eks-workshop --addon-name vpc-cni --query "addon.{Version:addonVersion,Status:status}" --output table
aws eks describe-addon --cluster-name eks-workshop --addon-name coredns --query "addon.{Version:addonVersion,Status:status}" --output table
aws eks describe-addon --cluster-name eks-workshop --addon-name kube-proxy --query "addon.{Version:addonVersion,Status:status}" --output table
```

---

## 9.6 Verify Everything

```bash
# Cluster version
aws eks describe-cluster --name eks-workshop --query "cluster.version" --output text
# Expected: 1.34

# All nodes on new version
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion
# Expected: all showing v1.34.x

# All pods healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# Add-ons healthy
aws eks describe-addon --cluster-name eks-workshop --addon-name vpc-cni --query "addon.status" --output text
aws eks describe-addon --cluster-name eks-workshop --addon-name coredns --query "addon.status" --output text
aws eks describe-addon --cluster-name eks-workshop --addon-name kube-proxy --query "addon.status" --output text
```

---

## Summary

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Before                         After                      │
│                                                             │
│   Control Plane: 1.33    →      Control Plane: 1.34        │
│   Nodes: 1.33 AMI       →      Nodes: 1.34 AMI            │
│   Add-ons: old versions  →      Add-ons: latest            │
│                                                             │
│   Total downtime: Zero                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key takeaways:

- ✅ Always upgrade **one minor version** at a time
- ✅ Always check **upgrade insights** before starting
- ✅ Follow the order: **CP → Nodes → Add-ons**
- ✅ Managed node groups perform a **rolling update** — zero downtime
- ✅ Use **PodDisruptionBudgets** to protect workloads during node rotation
- ✅ Upgrade your `kubectl` client to match the new cluster version
