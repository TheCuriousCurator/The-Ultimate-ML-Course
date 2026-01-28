#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Load Balancer Controller Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Variables
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "\n${YELLOW}AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${YELLOW}Cluster Name: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"

# Create IAM policy for ALB controller
echo -e "\n${YELLOW}Creating IAM policy for ALB controller...${NC}"
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

# Check if policy already exists
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo -e "${YELLOW}Policy already exists, skipping creation...${NC}"
else
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam-policy.json
    echo -e "${GREEN}✓ IAM policy created${NC}"
fi

# Create IAM service account
echo -e "\n${YELLOW}Creating IAM service account for ALB controller...${NC}"
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --approve

# Install cert-manager (required by ALB controller)
echo -e "\n${YELLOW}Installing cert-manager...${NC}"
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Install AWS Load Balancer Controller using Helm
echo -e "\n${YELLOW}Installing AWS Load Balancer Controller...${NC}"

# Add EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=$REGION \
    --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Wait for controller to be ready
echo -e "\n${YELLOW}Waiting for ALB controller to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=300s

# Verify installation
echo -e "\n${YELLOW}Verifying ALB controller installation...${NC}"
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Cleanup
rm -f iam-policy.json

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ AWS Load Balancer Controller Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nNext step: Run ./3-install-kserve.sh"
