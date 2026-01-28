#!/bin/bash
set -e

# Cleanup script for failed installations
# Use this if you need to start fresh after a failed installation

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Cleanup Failed Installation${NC}"
echo -e "${YELLOW}========================================${NC}"

echo -e "\n${RED}WARNING: This will remove KServe, Knative, and cert-manager${NC}"
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete KServe
echo -e "\n${YELLOW}Removing KServe...${NC}"
kubectl delete -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-cluster-resources.yaml --ignore-not-found=true
kubectl delete -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml --ignore-not-found=true

# Delete Knative
echo -e "\n${YELLOW}Removing Knative Serving...${NC}"
# Delete custom Kourier service first (if it exists)
kubectl delete -f ../manifests/kourier-service.yaml --ignore-not-found=true 2>/dev/null || true
kubectl delete -f https://github.com/knative/net-kourier/releases/download/knative-v1.15.0/kourier.yaml --ignore-not-found=true
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-core.yaml --ignore-not-found=true
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-crds.yaml --ignore-not-found=true

# Delete cert-manager
echo -e "\n${YELLOW}Removing cert-manager...${NC}"
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml --ignore-not-found=true

# Delete gp3 StorageClass if it exists
echo -e "\n${YELLOW}Removing gp3 StorageClass...${NC}"
kubectl delete storageclass gp3 --ignore-not-found=true

# Delete namespaces
echo -e "\n${YELLOW}Removing namespaces...${NC}"
kubectl delete namespace mlflow-kserve-test --ignore-not-found=true
kubectl delete namespace kserve --ignore-not-found=true
kubectl delete namespace knative-serving --ignore-not-found=true
kubectl delete namespace cert-manager --ignore-not-found=true

echo -e "\n${YELLOW}Waiting for namespaces to be fully deleted (this may take a minute)...${NC}"
sleep 30

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nYou can now re-run the installation scripts:"
echo -e "  ./2-setup-alb-controller.sh"
echo -e "  ./3-install-kserve.sh"
