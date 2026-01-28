#!/bin/bash

# Script to get the external URL for accessing the inference service on EKS

NAMESPACE="mlflow-kserve-test"
ISVC_NAME="mlflow-wine-classifier"

echo "=========================================="
echo "Getting Inference Service URL on EKS"
echo "=========================================="

# Check if InferenceService exists
echo -e "\n1. Checking InferenceService status..."
if ! kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE &>/dev/null; then
    echo "❌ InferenceService '$ISVC_NAME' not found in namespace '$NAMESPACE'"
    echo "Available InferenceServices:"
    kubectl get inferenceservice -n $NAMESPACE
    exit 1
fi

# Get InferenceService status
READY=$(kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$READY" != "True" ]; then
    echo "⚠️  InferenceService is not ready yet"
    echo "Current status:"
    kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE
    echo -e "\nWait for it to be ready with:"
    echo "  kubectl wait --for=condition=Ready inferenceservice/$ISVC_NAME -n $NAMESPACE --timeout=5m"
    exit 1
fi

echo "✓ InferenceService is ready"

# Get the predictor URL (this is the actual endpoint)
PREDICTOR_URL=$(kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE -o jsonpath='{.status.components.predictor.url}' 2>/dev/null || echo "")

# Fallback to Knative Service if predictor URL not available
if [ -z "$PREDICTOR_URL" ]; then
    PREDICTOR_URL=$(kubectl get ksvc ${ISVC_NAME}-predictor -n $NAMESPACE -o jsonpath='{.status.url}' 2>/dev/null || echo "")
fi

if [ -z "$PREDICTOR_URL" ]; then
    echo "⚠️  Could not get predictor URL"
    echo "Checking available services..."
    kubectl get ksvc -n $NAMESPACE
    exit 1
fi

echo -e "\n2. Predictor URL: $PREDICTOR_URL"

# Extract hostname for Host header
SERVICE_HOSTNAME=$(echo $PREDICTOR_URL | sed 's|http://||' | sed 's|https://||' | cut -d'/' -f1)

# Get the external load balancer endpoint
echo -e "\n3. Getting external load balancer endpoint..."

# Try Kourier in kourier-system (EKS setup)
INGRESS_HOST=$(kubectl get svc -n kourier-system kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n kourier-system kourier -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

# Fallback to knative-serving namespace
if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                   kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

# If still not found, try Istio
if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                   kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

if [ -z "$INGRESS_HOST" ]; then
    echo "⚠️  External load balancer not yet provisioned"
    echo "This typically takes 2-3 minutes after cluster creation"
    echo -e "\nTo watch for the external endpoint:"
    echo "  kubectl get svc -n kourier-system kourier -w"
    echo -e "\nCheck LoadBalancer status:"
    echo "  kubectl get svc kourier -n kourier-system"
    echo -e "\nAlternatively, use port-forward for local testing:"
    echo "  kubectl port-forward -n $NAMESPACE svc/${ISVC_NAME}-predictor-default 8080:80"
    exit 1
fi

echo "✓ External endpoint: $INGRESS_HOST"

# Check if LoadBalancer is internet-facing (EKS-specific)
if command -v aws &> /dev/null; then
    echo -e "\n4. Verifying LoadBalancer configuration..."
    LB_SCHEME=$(aws elbv2 describe-load-balancers --region us-east-1 2>/dev/null \
        --query "LoadBalancers[?contains(DNSName, '$(echo $INGRESS_HOST | cut -d'-' -f1-3)')].Scheme" \
        --output text 2>/dev/null || echo "")

    if [ "$LB_SCHEME" = "internet-facing" ]; then
        echo "✓ LoadBalancer is internet-facing (publicly accessible)"
    elif [ "$LB_SCHEME" = "internal" ]; then
        echo "⚠️  WARNING: LoadBalancer is INTERNAL (not publicly accessible)"
        echo "   This will only work from within the VPC"
        echo "   To fix: kubectl delete svc kourier -n kourier-system"
        echo "           kubectl apply -f manifests/kourier-service.yaml"
    fi
fi

# Display usage instructions
echo -e "\n=========================================="
echo "✓ Inference Service is Ready!"
echo "=========================================="

echo -e "\n📍 ACCESS METHODS:"
echo -e "\n1️⃣  External Access (Production):"
echo "   LoadBalancer URL: http://${INGRESS_HOST}"
echo "   Service Hostname: ${SERVICE_HOSTNAME}"
echo ""
echo "   ⚠️  IMPORTANT: You must use the Host header for routing!"

echo -e "\n   MLflow Native Endpoint (/invocations):"
echo "   curl -H 'Host: ${SERVICE_HOSTNAME}' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d @test/input_invocations.json \\"
echo "     http://${INGRESS_HOST}/invocations"

echo -e "\n   V2 Protocol Endpoint (/v2/models/.../infer):"
echo "   curl -H 'Host: ${SERVICE_HOSTNAME}' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d @test/input.json \\"
echo "     http://${INGRESS_HOST}/v2/models/wine-quality-elasticnet/infer"

echo -e "\n   🔄 Or use the automated test scripts:"
echo "   ./test_inference.sh          # Tests MLflow endpoint"
echo "   ./test_inference-mlserver.sh # Tests V2 endpoint"

echo -e "\n2️⃣  Port-Forward (Local Testing/Debug):"
echo "   kubectl port-forward -n $NAMESPACE svc/${ISVC_NAME}-predictor-default 8080:80"
echo "   curl -X POST http://localhost:8080/invocations -d @test/input_invocations.json"

echo -e "\n📊 MONITORING:"
echo "   View logs:    kubectl logs -n $NAMESPACE -l serving.kserve.io/inferenceservice=$ISVC_NAME"
echo "   Check status: kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE"
echo "   View pods:    kubectl get pods -n $NAMESPACE"

echo -e "\n💡 TIP: Add this to your /etc/hosts for easier access:"
echo "   $INGRESS_HOST $SERVICE_HOSTNAME"
echo "   Then you can use: curl http://$SERVICE_HOSTNAME/invocations -d @test/input_invocations.json"
echo "   (Note: This bypasses the need for -H 'Host: ...' header)"

# Export for scripting
echo -e "\n📋 ENVIRONMENT VARIABLES (copy to use in scripts):"
echo "export INGRESS_HOST='$INGRESS_HOST'"
echo "export SERVICE_HOSTNAME='$SERVICE_HOSTNAME'"
echo "export INFERENCE_URL='http://${INGRESS_HOST}'"
echo ""
echo "# Then use in your code:"
echo "curl -H \"Host: \${SERVICE_HOSTNAME}\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d @test/input_invocations.json \\"
echo "  \${INFERENCE_URL}/invocations"

echo -e "\n🔧 TROUBLESHOOTING:"
echo "   If you get connection timeout:"
echo "     - Check LoadBalancer is internet-facing (see warning above)"
echo "     - Verify security groups allow inbound traffic"
echo "     - Wait 2-3 minutes after LoadBalancer creation"
echo ""
echo "   If you get 404 errors:"
echo "     - Ensure you're using the correct Host header"
echo "     - Verify service hostname includes '-predictor'"
echo "     - Check: kubectl get ksvc -n $NAMESPACE"
echo ""
echo "   View detailed docs: cat TROUBLESHOOTING.md"
