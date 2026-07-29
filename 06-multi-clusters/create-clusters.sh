#!/bin/bash
set -e

echo ""
echo "======================================"
echo "  Module 6 - Multi-Cluster Setup"
echo "======================================"
echo ""

REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null)}
ARGOCD_CLUSTER="eks-workshop"

# Get VPC and subnets from existing cluster
echo "[1/4] Discovering network configuration..."
VPC_ID=$(aws eks describe-cluster --name $ARGOCD_CLUSTER --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Find private subnets with NAT gateway route
NAT_GW=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query "NatGateways[0].NatGatewayId" --output text)
NAT_RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=route.nat-gateway-id,Values=$NAT_GW" --query "RouteTables[].RouteTableId" --output text)
NAT_SUBNETS=$(aws ec2 describe-route-tables --route-table-ids $NAT_RT --query "RouteTables[].Associations[].SubnetId" --output text | tr '\t' ',')

echo "✔ VPC: $VPC_ID"
echo "✔ NAT Gateway: $NAT_GW"
echo "✔ Private Subnets (with NAT): $NAT_SUBNETS"
echo ""

# Create both clusters in parallel
echo "[2/4] Creating EKS clusters (this takes ~15 minutes)..."
echo ""
echo "  ☕ Good time for a break!"
echo ""

eksctl create cluster \
  --name dev-cluster \
  --region $REGION \
  --version 1.33 \
  --vpc-private-subnets $NAT_SUBNETS \
  --without-nodegroup \
  2>&1 | sed 's/^/  [dev] /' &
DEV_PID=$!

eksctl create cluster \
  --name prod-cluster \
  --region $REGION \
  --version 1.33 \
  --vpc-private-subnets $NAT_SUBNETS \
  --without-nodegroup \
  2>&1 | sed 's/^/  [prod] /' &
PROD_PID=$!

wait $DEV_PID
echo "  ✔ dev-cluster created"
wait $PROD_PID
echo "  ✔ prod-cluster created"

echo ""

# Enable private endpoint (public + private)
echo "[3/4] Enabling private API endpoints..."
aws eks update-cluster-config --name dev-cluster --region $REGION \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true > /dev/null
aws eks update-cluster-config --name prod-cluster --region $REGION \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true > /dev/null
echo "✔ Private endpoints enabled"

echo ""

# Create node groups
echo "[4/4] Creating node groups..."

eksctl create nodegroup \
  --cluster dev-cluster \
  --name dev-nodes \
  --region $REGION \
  --node-type m5.large \
  --nodes 2 \
  --node-private-networking \
  --subnet-ids $NAT_SUBNETS \
  --managed \
  2>&1 | sed 's/^/  [dev] /' &
DEV_NG_PID=$!

eksctl create nodegroup \
  --cluster prod-cluster \
  --name prod-nodes \
  --region $REGION \
  --node-type m5.large \
  --nodes 2 \
  --node-private-networking \
  --subnet-ids $NAT_SUBNETS \
  --managed \
  2>&1 | sed 's/^/  [prod] /' &
PROD_NG_PID=$!

wait $DEV_NG_PID
echo "  ✔ dev-cluster nodes ready"
wait $PROD_NG_PID
echo "  ✔ prod-cluster nodes ready"

echo ""

# Switch back to ArgoCD cluster
aws eks update-kubeconfig --name $ARGOCD_CLUSTER --region $REGION

echo ""
echo "======================================"
echo "  Multi-Cluster Setup Complete"
echo "======================================"
echo ""
echo "  ArgoCD Cluster: $ARGOCD_CLUSTER"
echo "  Dev Cluster:    dev-cluster"
echo "  Prod Cluster:   prod-cluster"
echo "  Region:         $REGION"
echo ""
echo "======================================"
echo ""
