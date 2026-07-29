#!/bin/bash
set -e

echo ""
echo "======================================"
echo "  Module 8 - Managed ArgoCD Setup"
echo "======================================"
echo ""
echo "  Pre-requisite: Ensure your IDE role has permissions."
echo "  If you haven't run the grant-permissions step, run it now."
echo ""

REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null)}
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

echo "[1/6] Region: $REGION | Account: $ACCOUNT_ID"
echo ""

# -------------------------------------------
# Step 2: Create VPC with private subnets + NAT
# -------------------------------------------
echo "[2/6] Creating VPC with private subnets and NAT gateway..."

VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=argocd-managed-vpc

# Get AZs
AZ1=$(aws ec2 describe-availability-zones --region $REGION --query "AvailabilityZones[0].ZoneName" --output text)
AZ2=$(aws ec2 describe-availability-zones --region $REGION --query "AvailabilityZones[1].ZoneName" --output text)

# Public subnets (for NAT gateway)
PUB_SUBNET1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone $AZ1 --query "Subnet.SubnetId" --output text)
PUB_SUBNET2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone $AZ2 --query "Subnet.SubnetId" --output text)
aws ec2 create-tags --resources $PUB_SUBNET1 --tags Key=Name,Value=argocd-public-1
aws ec2 create-tags --resources $PUB_SUBNET2 --tags Key=Name,Value=argocd-public-2

# Private subnets (for EKS clusters)
PRIV_SUBNET1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.10.0/24 --availability-zone $AZ1 --query "Subnet.SubnetId" --output text)
PRIV_SUBNET2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 --availability-zone $AZ2 --query "Subnet.SubnetId" --output text)
aws ec2 create-tags --resources $PRIV_SUBNET1 --tags Key=Name,Value=argocd-private-1
aws ec2 create-tags --resources $PRIV_SUBNET2 --tags Key=Name,Value=argocd-private-2

# Internet Gateway
IGW=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=argocd-igw

# Public route table
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET1 > /dev/null
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_SUBNET2 > /dev/null

# NAT Gateway (in public subnet)
EIP=$(aws ec2 allocate-address --domain vpc --query "AllocationId" --output text)
NAT_GW=$(aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET1 --allocation-id $EIP --query "NatGateway.NatGatewayId" --output text)
aws ec2 create-tags --resources $NAT_GW --tags Key=Name,Value=argocd-nat

echo "  Waiting for NAT gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW

# Private route table (routes through NAT)
PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET1 > /dev/null
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_SUBNET2 > /dev/null

echo "✔ VPC: $VPC_ID"
echo "✔ Private Subnets: $PRIV_SUBNET1, $PRIV_SUBNET2"
echo "✔ NAT Gateway: $NAT_GW"
echo ""

# -------------------------------------------
# Step 3: Create Hub Cluster (ArgoCD lives here)
# -------------------------------------------
echo "[3/6] Creating hub-cluster (for managed ArgoCD capability)..."

eksctl create cluster \
  --name hub-cluster \
  --region $REGION \
  --version 1.33 \
  --vpc-private-subnets $PRIV_SUBNET1,$PRIV_SUBNET2 \
  --without-nodegroup 2>&1 | sed 's/^/  [hub] /' &
HUB_PID=$!

# -------------------------------------------
# Step 4: Create Workload Cluster (deploy apps here)
# -------------------------------------------
echo "[4/6] Creating workload-cluster (deploy applications here)..."

eksctl create cluster \
  --name workload-cluster \
  --region $REGION \
  --version 1.33 \
  --vpc-private-subnets $PRIV_SUBNET1,$PRIV_SUBNET2 \
  --without-nodegroup 2>&1 | sed 's/^/  [workload] /' &
WORKLOAD_PID=$!

# Wait for both
wait $HUB_PID
echo "  ✔ hub-cluster created"
wait $WORKLOAD_PID
echo "  ✔ workload-cluster created"

echo ""

# -------------------------------------------
# Step 5: Configure API endpoints
# -------------------------------------------
echo "[5/6] Configuring API endpoints..."

aws eks update-cluster-config --name hub-cluster --region $REGION \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true > /dev/null

aws eks update-cluster-config --name workload-cluster --region $REGION \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true > /dev/null

echo "✔ API endpoints configured"
echo ""
echo "  Waiting for clusters to become ACTIVE after endpoint update..."
aws eks wait cluster-active --name hub-cluster --region $REGION
aws eks wait cluster-active --name workload-cluster --region $REGION
echo "✔ Both clusters ACTIVE"
echo ""

# -------------------------------------------
# Step 6: Create Node Groups
# -------------------------------------------
echo "[6/6] Creating managed node groups..."

# Create node IAM role
NODE_ROLE_NAME="argocd-workshop-node-role"
if ! aws iam get-role --role-name $NODE_ROLE_NAME &>/dev/null; then
  aws iam create-role \
    --role-name $NODE_ROLE_NAME \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {"Service": "ec2.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }
      ]
    }' > /dev/null
  aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
  aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  echo "  ✔ Node IAM role created"
else
  echo "  ✔ Node IAM role already exists"
fi

NODE_ROLE_ARN=$(aws iam get-role --role-name $NODE_ROLE_NAME --query "Role.Arn" --output text)

# Get subnets per cluster
HUB_SUBNETS=$(aws eks describe-cluster --name hub-cluster --region $REGION --query "cluster.resourcesVpcConfig.subnetIds[*]" --output text | tr '\t' ' ')
WORKLOAD_SUBNETS=$(aws eks describe-cluster --name workload-cluster --region $REGION --query "cluster.resourcesVpcConfig.subnetIds[*]" --output text | tr '\t' ' ')

# Create node groups via AWS API (no kubectl/eksctl access needed)
aws eks create-nodegroup \
  --cluster-name hub-cluster \
  --nodegroup-name hub-nodes \
  --node-role $NODE_ROLE_ARN \
  --subnets $HUB_SUBNETS \
  --instance-types m5.large \
  --scaling-config minSize=2,maxSize=2,desiredSize=2 \
  --region $REGION > /dev/null

aws eks create-nodegroup \
  --cluster-name workload-cluster \
  --nodegroup-name workload-nodes \
  --node-role $NODE_ROLE_ARN \
  --subnets $WORKLOAD_SUBNETS \
  --instance-types m5.large \
  --scaling-config minSize=2,maxSize=2,desiredSize=2 \
  --region $REGION > /dev/null

echo "  Waiting for node groups to become active..."
aws eks wait nodegroup-active --cluster-name hub-cluster --nodegroup-name hub-nodes --region $REGION &
aws eks wait nodegroup-active --cluster-name workload-cluster --nodegroup-name workload-nodes --region $REGION &
wait

echo "  ✔ hub-cluster nodes ready"
echo "  ✔ workload-cluster nodes ready"

echo ""
echo "======================================"
echo "  Infrastructure Ready"
echo "======================================"
echo ""
echo "  VPC:              $VPC_ID"
echo "  Hub Cluster:      hub-cluster (private)"
echo "  Workload Cluster: workload-cluster (private)"
echo "  Region:           $REGION"
echo ""
echo "  Next Steps (via Console):"
echo "    1. Enable Identity Center"
echo "    2. Create a user"
echo "    3. Create ArgoCD Capability on hub-cluster"
echo "    4. Add workload-cluster access entry"
echo ""
echo "======================================"
echo ""
