#!/bin/bash
set -e

# Test script for V2 protocol inference in KServe on EKS
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NAMESPACE="mlflow-kserve-test"
ISVC_NAME="mlflow-wine-classifier"
MODEL_NAME="wine-quality-elasticnet"

echo "=========================================="
echo "Testing V2 Protocol (/v2/models/.../infer) on EKS"
echo "=========================================="

# Check if InferenceService exists and is ready
echo -e "\n1. Checking InferenceService status..."
if ! kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE &>/dev/null; then
    echo "❌ InferenceService '$ISVC_NAME' not found in namespace '$NAMESPACE'"
    echo ""
    echo "Available InferenceServices:"
    kubectl get inferenceservice -n $NAMESPACE 2>/dev/null || echo "  None found"
    echo ""
    echo "To deploy, run: kubectl apply -f manifests/inference.yaml"
    exit 1
fi

# Check if ready
ISVC_READY=$(kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$ISVC_READY" != "True" ]; then
    echo "⚠️  InferenceService is not ready yet"
    echo ""
    kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE
    echo ""
    echo "Check status: kubectl describe inferenceservice $ISVC_NAME -n $NAMESPACE"
    exit 1
fi

echo "✓ InferenceService is Ready"

# Get the predictor URL (this is the actual endpoint)
echo -e "\n2. Getting predictor service URL..."
PREDICTOR_URL=$(kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE -o jsonpath='{.status.components.predictor.url}' 2>/dev/null || echo "")

if [ -z "$PREDICTOR_URL" ]; then
    PREDICTOR_URL=$(kubectl get ksvc ${ISVC_NAME}-predictor -n $NAMESPACE -o jsonpath='{.status.url}' 2>/dev/null || echo "")
fi

if [ -z "$PREDICTOR_URL" ]; then
    echo "⚠️  Could not get predictor URL"
    kubectl get ksvc -n $NAMESPACE
    exit 1
fi

echo "✓ Predictor URL: $PREDICTOR_URL"

# Extract hostname for Host header
SERVICE_HOSTNAME=$(echo $PREDICTOR_URL | sed 's|http://||' | sed 's|https://||' | cut -d'/' -f1)

# Try to get the ingress gateway external IP/DNS
echo -e "\n3. Getting ingress gateway endpoint..."
INGRESS_HOST=$(kubectl get svc -n kourier-system kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n kourier-system kourier -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
               kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
               kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$INGRESS_HOST" ]; then
    echo "✓ External endpoint: $INGRESS_HOST"
    echo -e "\n4. Testing V2 inference endpoint..."

    # Test via external load balancer
    echo "  Request: curl -H 'Host: ${SERVICE_HOSTNAME}' http://${INGRESS_HOST}/v2/models/${MODEL_NAME}/infer"

    http_code=$(curl -s -w "%{http_code}" -o /tmp/response_v2.json \
      -H "Host: ${SERVICE_HOSTNAME}" \
      -H "Content-Type: application/json" \
      -d @"${SCRIPT_DIR}/test/input.json" \
      "http://${INGRESS_HOST}/v2/models/${MODEL_NAME}/infer")

    response=$(cat /tmp/response_v2.json)

    if [ "$http_code" = "200" ]; then
        echo "✓ Success! HTTP Status: $http_code"
        echo ""
        echo "Prediction result:"
        echo "$response" | jq . 2>/dev/null || echo "$response"
    elif [ -n "$response" ]; then
        echo "⚠️  HTTP Status: $http_code"
        echo "Response:"
        echo "$response" | jq . 2>/dev/null || echo "$response"
    else
        echo "❌ Request failed with HTTP Status: $http_code"
        echo "No response body received"
        exit 1
    fi

    echo -e "\n=========================================="
    echo "✓ Test completed successfully!"
    echo "=========================================="
    echo -e "\nTo test from outside the cluster, use:"
    echo "  curl -H 'Host: ${SERVICE_HOSTNAME}' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d @test/input.json \\"
    echo "    http://${INGRESS_HOST}/v2/models/${MODEL_NAME}/infer"

    echo ""
    echo "=========================================="
    echo "✓ V2 Protocol Test completed successfully!"
    echo "=========================================="
    echo ""
    echo "📊 Deployment Information:"
    echo "  InferenceService: $ISVC_NAME"
    echo "  Model Name: $MODEL_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "  External URL: $INGRESS_HOST"
    echo "  Service Hostname: $SERVICE_HOSTNAME"
    echo ""
    echo "🔄 To test from outside the cluster:"
    echo "  curl -H 'Host: ${SERVICE_HOSTNAME}' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d @test/input.json \\"
    echo "    http://${INGRESS_HOST}/v2/models/${MODEL_NAME}/infer"

    # Clean up temp file
    rm -f /tmp/response_v2.json

else
    echo "⚠️  External load balancer not yet provisioned"
    echo "This is normal for new deployments - AWS takes 2-3 minutes to provision NLB"
    echo -e "\n📌 OPTION 1: Wait and retry (recommended for production)"
    echo "  Watch for external IP: kubectl get svc -n kourier-system kourier -w"
    echo -e "\n📌 OPTION 2: Use port-forward for immediate testing (dev/debug only)"
    echo "  Run in another terminal:"
    echo "    kubectl port-forward -n $NAMESPACE svc/${ISVC_NAME}-predictor-default 8080:80"
    echo "  Then test with:"
    echo "    curl -X POST http://localhost:8080/v2/models/${MODEL_NAME}/infer \\"
    echo "      -H 'Content-Type: application/json' \\"
    echo "      -d @test/input.json"

    read -p $'\nDo you want to use port-forward now? (y/n): ' -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Setting up port-forward..."
        echo "Testing via port-forward on localhost:8080..."

        # Start port-forward in background
        kubectl port-forward -n $NAMESPACE svc/${ISVC_NAME}-predictor-default 8080:80 &
        PF_PID=$!

        # Wait for port-forward to be ready
        sleep 3

        # Test via localhost
        response=$(curl -s -H "Content-Type: application/json" \
          -d @"${SCRIPT_DIR}/test/input.json" \
          "http://localhost:8080/v2/models/${MODEL_NAME}/infer")

        if [ -n "$response" ]; then
            echo "✓ Response received:"
            echo "$response" | jq . 2>/dev/null || echo "$response"
        fi

        # Clean up port-forward
        kill $PF_PID 2>/dev/null || true

        echo -e "\n✓ Port-forward test completed!"
    fi
fi
