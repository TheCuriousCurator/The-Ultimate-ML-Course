#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploy MLflow Server on EKS${NC}"
echo -e "${GREEN}========================================${NC}"

# Variables
NAMESPACE="mlflow-kserve-test"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}"

echo -e "\nNamespace: $NAMESPACE"
echo -e "S3 Bucket: $BUCKET_NAME"

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}✗ Namespace $NAMESPACE not found. Please run script 3 first.${NC}"
    exit 1
fi

# Check if S3 bucket exists
if ! aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
    echo -e "${RED}✗ S3 bucket $BUCKET_NAME not found. Please run script 4 first.${NC}"
    exit 1
fi

# Check if service account exists
if ! kubectl get serviceaccount kserve-sa -n $NAMESPACE &>/dev/null; then
    echo -e "${RED}✗ Service account kserve-sa not found. Please run script 4 first.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Prerequisites met${NC}"

# Check and create gp3 StorageClass if it doesn't exist
echo -e "\n${YELLOW}Checking for gp3 StorageClass...${NC}"
if ! kubectl get storageclass gp3 &>/dev/null; then
    echo -e "${YELLOW}gp3 StorageClass not found. Creating it...${NC}"

    # Create gp3 StorageClass manifest
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  iops: "3000"
  throughput: "125"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

    echo -e "${GREEN}✓ gp3 StorageClass created${NC}"
else
    echo -e "${GREEN}✓ gp3 StorageClass already exists${NC}"
fi

# Update the manifest with the correct bucket name
echo -e "\n${YELLOW}Updating MLflow manifest with bucket name...${NC}"
sed "s/REPLACE_WITH_YOUR_BUCKET_NAME/$BUCKET_NAME/g" ../manifests/mlflow-server.yaml > /tmp/mlflow-server-configured.yaml

# Deploy MLflow
echo -e "\n${YELLOW}Deploying MLflow server...${NC}"
kubectl apply -f /tmp/mlflow-server-configured.yaml

# Wait for deployment to be ready
echo -e "\n${YELLOW}Waiting for MLflow server to be ready...${NC}"
echo -e "${YELLOW}Note: First startup takes ~30-40 seconds while boto3 is installed${NC}"
kubectl wait --for=condition=available deployment/mlflow-server -n $NAMESPACE --timeout=300s

# Get the external URL
echo -e "\n${YELLOW}Getting MLflow server URL...${NC}"
for i in {1..30}; do
    MLFLOW_URL=$(kubectl get svc mlflow-server -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                 kubectl get svc mlflow-server -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$MLFLOW_URL" ]; then
        break
    fi
    echo -e "Waiting for load balancer... ($i/30)"
    sleep 10
done

# Clean up temp file
rm -f /tmp/mlflow-server-configured.yaml

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ MLflow Server Deployed!${NC}"
echo -e "${GREEN}========================================${NC}"

if [ -n "$MLFLOW_URL" ]; then
    echo -e "\n📍 MLflow Server URL: http://${MLFLOW_URL}:5000"
    echo -e "\n📋 Set these environment variables:"
    echo -e "export MLFLOW_TRACKING_URI=http://${MLFLOW_URL}:5000"
    echo -e "export MLFLOW_REGISTRY_URI=http://${MLFLOW_URL}:5000"

    echo -e "\n✅ Test connection:"
    echo -e "curl http://${MLFLOW_URL}:5000/health"

    echo -e "\n📊 Access MLflow UI:"
    echo -e "Open browser: http://${MLFLOW_URL}:5000"
else
    echo -e "\n${YELLOW}⚠ Load balancer URL not yet available${NC}"
    echo -e "Run this to get the URL once it's ready:"
    echo -e "  kubectl get svc mlflow-server -n $NAMESPACE"

    echo -e "\n📋 For internal cluster access (from training pods):"
    echo -e "export MLFLOW_TRACKING_URI=http://mlflow-server-internal.${NAMESPACE}.svc.cluster.local:5000"
fi

echo -e "\n💾 Data Storage:"
echo -e "  - Metadata: PersistentVolume (20GB gp3) at /mlflow/mlflow.db"
echo -e "  - Artifacts: S3 bucket s3://${BUCKET_NAME}/artifacts"
echo -e "  - boto3 & awscli: Installed automatically on container startup"

echo -e "\n🌐 Network Configuration:"
echo -e "  - LoadBalancer: Internet-facing (publicly accessible)"
echo -e "  - Type: Network Load Balancer (NLB)"
echo -e "  - Internal access: http://mlflow-server-internal.${NAMESPACE}.svc.cluster.local:5000"

echo -e "\n🔍 Useful Commands:"
echo -e "  View logs:    kubectl logs -f deployment/mlflow-server -n $NAMESPACE"
echo -e "  Check status: kubectl get pods -n $NAMESPACE -l app=mlflow-server"
echo -e "  Port-forward: kubectl port-forward -n $NAMESPACE svc/mlflow-server 5000:5000"
echo -e "  Verify boto3: kubectl logs deployment/mlflow-server -n $NAMESPACE | grep 'Successfully installed'"
