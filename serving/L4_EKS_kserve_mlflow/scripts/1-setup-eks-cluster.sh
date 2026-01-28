#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EKS Cluster Setup Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

command -v aws >/dev/null 2>&1 || { echo -e "${RED}aws CLI is not installed. Please install it first.${NC}" >&2; exit 1; }
command -v eksctl >/dev/null 2>&1 || { echo -e "${RED}eksctl is not installed. Please install it first.${NC}" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is not installed. Please install it first.${NC}" >&2; exit 1; }

# Verify AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "${RED}AWS credentials are not configured properly.${NC}" >&2; exit 1; }

echo -e "${GREEN}✓ All prerequisites met${NC}"

# Variables
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
CONFIG_FILE="../eks-cluster-config.yaml"

# Check if cluster already exists
echo -e "\n${YELLOW}Checking if cluster already exists...${NC}"
if eksctl get cluster --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    echo -e "${YELLOW}Cluster $CLUSTER_NAME already exists in region $REGION${NC}"
    read -p "Do you want to delete and recreate it? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Deleting existing cluster...${NC}"
        eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait
        echo -e "${GREEN}✓ Cluster deleted${NC}"
    else
        echo -e "${YELLOW}Using existing cluster${NC}"
        eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$REGION
        exit 0
    fi
fi

# Create EKS cluster
echo -e "\n${YELLOW}Creating EKS cluster (this will take 15-20 minutes)...${NC}"
eksctl create cluster -f $CONFIG_FILE

# Update kubeconfig
echo -e "\n${YELLOW}Updating kubeconfig...${NC}"
eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$REGION

# Verify cluster
echo -e "\n${YELLOW}Verifying cluster...${NC}"
kubectl cluster-info
kubectl get nodes

# Enable OIDC provider (should already be enabled by config, but let's verify)
echo -e "\n${YELLOW}Verifying OIDC provider...${NC}"
eksctl utils associate-iam-oidc-provider --cluster=$CLUSTER_NAME --region=$REGION --approve

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ EKS Cluster Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Cluster Name: $CLUSTER_NAME"
echo -e "Region: $REGION"
echo -e "\nNext steps:"
echo -e "  1. Run ./2-setup-alb-controller.sh"
echo -e "  2. Run ./3-install-kserve.sh"
