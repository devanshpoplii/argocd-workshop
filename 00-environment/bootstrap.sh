#!/bin/bash
set -e

echo ""
echo "======================================"
echo "  ArgoCD Workshop - Environment Setup"
echo "======================================"
echo ""

# -------------------------------------------
# Step 1: Detect AWS Region
# -------------------------------------------
echo "[1/5] Detecting AWS Region..."
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}

if [ -z "$REGION" ]; then
  echo "✗ Could not detect region. Please set AWS_REGION."
  exit 1
fi
echo "✔ Region: $REGION"
echo ""

# -------------------------------------------
# Step 2: Discover Cluster VPC
# -------------------------------------------
echo "[2/5] Discovering Cluster VPC..."
CLUSTER_NAME="eks-workshop"
VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "✗ Could not determine VPC for cluster '$CLUSTER_NAME'."
  exit 1
fi
echo "✔ VPC: $VPC_ID"
echo ""

# -------------------------------------------
# Step 3: Install AWS Load Balancer Controller
# -------------------------------------------
echo "[3/5] Installing AWS Load Balancer Controller..."

# Check if already installed
if kubectl get deployment aws-load-balancer-controller -n kube-system &>/dev/null; then
  echo "✔ AWS Load Balancer Controller already installed"
else
  # Get OIDC provider
  OIDC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --query "cluster.identity.oidc.issuer" \
    --output text | sed 's|https://||')

  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

  # Create IAM policy for LB controller (if not exists)
  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
  if ! aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
    curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json
    aws iam create-policy \
      --policy-name AWSLoadBalancerControllerIAMPolicy \
      --policy-document file://iam_policy.json \
      --region $REGION > /dev/null
    rm -f iam_policy.json
  fi

  # Create service account with IRSA
  eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --approve \
    --region=$REGION 2>/dev/null || true

  # Install via Helm
  helm repo add eks https://aws.github.io/eks-charts &>/dev/null
  helm repo update &>/dev/null

  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=$REGION \
    --set vpcId=$VPC_ID \
    --wait

  # Fix missing permission for newer LB controller versions
  LBC_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | grep -oP '(?<=role/).*')
  if [ -n "$LBC_ROLE" ]; then
    aws iam put-role-policy \
      --role-name $LBC_ROLE \
      --policy-name DescribeListenerAttributes \
      --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": "elasticloadbalancing:DescribeListenerAttributes",
            "Resource": "*"
          }
        ]
      }'
  fi

  echo "Waiting for controller to be ready..."
  kubectl wait --for=condition=available deployment/aws-load-balancer-controller \
    -n kube-system --timeout=120s
fi
echo "✔ AWS Load Balancer Controller ready"
echo ""

# -------------------------------------------
# Step 4: Create CodeCommit Repository
# -------------------------------------------
echo "[4/5] Creating CodeCommit Repository..."
REPO_NAME="argocd-workshop"

# Install git-remote-codecommit
pip install git-remote-codecommit -q

# Check if repo already exists
if aws codecommit get-repository --repository-name $REPO_NAME --region $REGION &>/dev/null; then
  echo "✔ Repository already exists"
else
  aws codecommit create-repository \
    --repository-name $REPO_NAME \
    --repository-description "ArgoCD Immersion Day Workshop" \
    --region $REGION > /dev/null
  echo "✔ Repository created"
fi

# Create IAM user for ArgoCD to access CodeCommit
CC_USER="argocd-codecommit"
if aws iam get-user --user-name $CC_USER &>/dev/null 2>&1; then
  echo "✔ IAM user '$CC_USER' already exists"
else
  aws iam create-user --user-name $CC_USER > /dev/null
  aws iam attach-user-policy --user-name $CC_USER --policy-arn arn:aws:iam::aws:policy/AWSCodeCommitReadOnly
  echo "✔ IAM user '$CC_USER' created with CodeCommit read access"
fi

# Generate HTTPS Git credentials for ArgoCD
CRED_OUTPUT=$(aws iam create-service-specific-credential \
  --user-name $CC_USER \
  --service-name codecommit.amazonaws.com 2>/dev/null)

if [ -n "$CRED_OUTPUT" ]; then
  CC_USERNAME=$(echo $CRED_OUTPUT | jq -r '.ServiceSpecificCredential.ServiceUserName')
  CC_PASSWORD=$(echo $CRED_OUTPUT | jq -r '.ServiceSpecificCredential.ServicePassword')
  echo "✔ Git credentials generated"
  echo ""
  echo "  ┌────────────────────────────────────────────────┐"
  echo "  │ Run the following commands to save credentials: │"
  echo "  ├────────────────────────────────────────────────┤"
  echo "  │ export CC_USERNAME=$CC_USERNAME"
  echo "  │ export CC_PASSWORD=$CC_PASSWORD"
  echo "  └────────────────────────────────────────────────┘"
  echo ""
else
  echo "⚠ Git credentials already exist. Using existing credentials."
fi

# Get clone URLs
HTTPS_URL=$(aws codecommit get-repository \
  --repository-name $REPO_NAME \
  --region $REGION \
  --query "repositoryMetadata.cloneUrlHttp" \
  --output text)

GRC_URL="codecommit::${REGION}://${REPO_NAME}"

echo ""
echo "  HTTPS Clone URL: $HTTPS_URL"
echo "  GRC Clone URL:   $GRC_URL"
echo ""

# -------------------------------------------
# Step 5: Complete
# -------------------------------------------
echo "[5/5] Bootstrap Complete!"
echo ""
echo "======================================"
echo "  Bootstrap Complete"
echo "======================================"
echo ""
echo "  Cluster:    $CLUSTER_NAME"
echo "  Region:     $REGION"
echo "  VPC:        $VPC_ID"
echo "  Repository: $REPO_NAME"
echo ""
echo "======================================"
echo ""