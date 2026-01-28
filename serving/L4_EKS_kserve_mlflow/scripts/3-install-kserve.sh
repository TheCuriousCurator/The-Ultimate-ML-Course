#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}KServe Installation Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Variables
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
KSERVE_VERSION="v0.16"

echo -e "\n${YELLOW}Installing KServe $KSERVE_VERSION...${NC}"

# Verify cert-manager (should already be installed from ALB controller setup)
echo -e "\n${YELLOW}Verifying cert-manager is already installed...${NC}"
if kubectl get namespace cert-manager &>/dev/null; then
    echo -e "${GREEN}✓ cert-manager already installed${NC}"
    kubectl get pods -n cert-manager
else
    echo -e "${RED}✗ cert-manager not found. Please run script 2 first.${NC}"
    exit 1
fi

# Install Knative Serving
echo -e "\n${YELLOW}Installing Knative Serving...${NC}"
KNATIVE_VERSION="v1.15.0"

# Install Knative CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml

# Install Knative core components
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml

# Install Kourier networking layer (lightweight alternative to Istio)
echo -e "\n${YELLOW}Installing Kourier networking layer...${NC}"
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml

# Configure Knative to use Kourier
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# Configure Knative domain (using sslip.io for automatic DNS)
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"example.com":""}}'

# Wait for Knative Serving to be ready
echo -e "\n${YELLOW}Waiting for Knative Serving to be ready (this may take a few minutes)...${NC}"
kubectl wait --for=condition=ready pod --all -n knative-serving --timeout=600s

# Configure Kourier LoadBalancer as internet-facing
echo -e "\n${YELLOW}Configuring Kourier LoadBalancer for external access...${NC}"
echo -e "${YELLOW}Note: By default, Kourier creates an internal LoadBalancer${NC}"
echo -e "${YELLOW}We'll reconfigure it to be internet-facing for external access${NC}"

# Wait a bit for Kourier service to be created
sleep 5

# Check if Kourier service exists
if kubectl get svc kourier -n kourier-system &>/dev/null; then
    # Delete the existing internal LoadBalancer
    kubectl delete svc kourier -n kourier-system
    echo -e "${YELLOW}Deleted internal Kourier LoadBalancer${NC}"

    # Apply the internet-facing configuration
    kubectl apply -f ../manifests/kourier-service.yaml
    echo -e "${GREEN}✓ Applied internet-facing Kourier LoadBalancer${NC}"

    # Wait for new LoadBalancer to be provisioned
    echo -e "\n${YELLOW}Waiting for internet-facing LoadBalancer to be provisioned (2-3 minutes)...${NC}"
    for i in {1..30}; do
        EXTERNAL_IP=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                      kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [ -n "$EXTERNAL_IP" ]; then
            echo -e "${GREEN}✓ LoadBalancer provisioned: $EXTERNAL_IP${NC}"
            break
        fi
        echo -e "Waiting for LoadBalancer... ($i/30)"
        sleep 10
    done
else
    echo -e "${YELLOW}⚠ Kourier service not found yet, will be configured later${NC}"
fi

# Install KServe
echo -e "\n${YELLOW}Installing KServe...${NC}"
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml

# Wait for KServe controller manager to be ready
echo -e "\n${YELLOW}Waiting for KServe controller manager to be ready...${NC}"
kubectl wait --for=condition=ready pod -l control-plane=kserve-controller-manager -n kserve --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Still waiting for controller manager...${NC}"
    for i in {1..20}; do
        if kubectl get pods -n kserve -l control-plane=kserve-controller-manager | grep -q "Running"; then
            echo -e "${GREEN}✓ KServe controller is running${NC}"
            break
        fi
        echo -e "Waiting for KServe controller... ($i/20)"
        sleep 10
    done
}

# Wait for webhook endpoints to be available
echo -e "\n${YELLOW}Waiting for webhook endpoints to be ready...${NC}"
for i in {1..30}; do
    ENDPOINTS=$(kubectl get endpoints kserve-webhook-server-service -n kserve -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -n "$ENDPOINTS" ]; then
        echo -e "${GREEN}✓ Webhook endpoints are ready${NC}"
        break
    fi
    echo -e "Waiting for webhook endpoints... ($i/30)"
    sleep 10
done

# Additional wait to ensure webhook is fully functional
echo -e "${YELLOW}Ensuring webhook is fully functional...${NC}"
sleep 20

# Install KServe built-in ClusterServingRuntimes (now that webhook is ready)
echo -e "\n${YELLOW}Installing KServe ClusterServingRuntimes...${NC}"
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-cluster-resources.yaml

echo -e "${GREEN}✓ KServe ClusterServingRuntimes installed${NC}"

# Create namespace for ML workloads
echo -e "\n${YELLOW}Creating namespace for ML workloads...${NC}"
kubectl create namespace mlflow-kserve-test --dry-run=client -o yaml | kubectl apply -f -

# Configure KServe for raw deployment mode (optional - uncomment if you prefer raw k8s deployments over serverless)
# echo -e "\n${YELLOW}Configuring KServe for raw deployment mode...${NC}"
# kubectl patch configmap/inferenceservice-config -n kserve --type=strategic -p '{"data": {"deploy": "{\"defaultDeploymentMode\": \"RawDeployment\"}"}}'

# Verify installations
echo -e "\n${YELLOW}Verifying installations...${NC}"
echo -e "\nKnative Serving pods:"
kubectl get pods -n knative-serving

echo -e "\nKServe pods:"
kubectl get pods -n kserve

echo -e "\nCert-manager pods:"
kubectl get pods -n cert-manager

echo -e "\nNamespaces:"
kubectl get ns | grep -E "knative|kserve|mlflow"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ KServe Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

# Display Kourier LoadBalancer information
echo -e "\n🌐 ${YELLOW}Kourier Ingress Gateway:${NC}"
KOURIER_LB=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
             kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$KOURIER_LB" ]; then
    echo -e "  External URL: http://${KOURIER_LB}"
    echo -e "  Status: ${GREEN}Internet-facing (publicly accessible)${NC}"
else
    echo -e "  ${YELLOW}LoadBalancer still provisioning...${NC}"
    echo -e "  Check status: kubectl get svc kourier -n kourier-system"
fi

echo -e "\n📦 ${YELLOW}Deployment Information:${NC}"
echo -e "  Namespace for ML workloads: mlflow-kserve-test"
echo -e "  KServe version: 0.13.0"
echo -e "  Knative Serving: Installed with Kourier networking"

echo -e "\n🚀 ${YELLOW}Next Steps:${NC}"
echo -e "  1. Setup S3 and IAM: ./4-setup-s3-mlflow.sh"
echo -e "  2. Deploy MLflow (optional): ./6-deploy-mlflow-on-eks.sh"
echo -e "  3. Deploy your model: kubectl apply -f ../manifests/inference.yaml"
echo -e "  4. Test inference: cd .. && ./test_inference.sh"

echo -e "\n🔍 ${YELLOW}Useful Commands:${NC}"
echo -e "  Check InferenceService: kubectl get inferenceservice -n mlflow-kserve-test"
echo -e "  View logs: kubectl logs -n kserve -l control-plane=kserve-controller-manager"
echo -e "  Get Kourier URL: kubectl get svc kourier -n kourier-system"
