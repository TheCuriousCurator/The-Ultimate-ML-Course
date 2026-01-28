#!/bin/bash
set -e

# Configuration
MODEL_NAME="wine-quality-elasticnet"
BUILD_DIR="/tmp/mlflow_v2_build"

echo "Setting up build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Get latest version from MLFlow
source ../.venv/bin/activate
VERSION=$(python3 -c "
import mlflow
client = mlflow.tracking.MlflowClient()
versions = client.get_latest_versions('${MODEL_NAME}', stages=['None'])
print(versions[0].version if versions else '')
")

if [ -z "$VERSION" ]; then
    echo "Error: No model versions found"
    exit 1
fi

echo "Found model version: $VERSION"
IMAGE_NAME="dksahuji/${MODEL_NAME}:${VERSION}"

# Download model
echo "Downloading model..."
python3 -c "
import mlflow
mlflow.artifacts.download_artifacts(
    artifact_uri='models:/${MODEL_NAME}/${VERSION}',
    dst_path='${BUILD_DIR}/model'
)
"

# Create model-settings.json for V2 protocol
cat > "${BUILD_DIR}/model/model-settings.json" << EOF
{
  "name": "${MODEL_NAME}",
  "implementation": "mlserver_mlflow.MLflowRuntime",
  "parameters": {
    "uri": "/mnt/models/${MODEL_NAME}"
  }
}
EOF

echo "Created model-settings.json"

# Create Dockerfile
cat > "${BUILD_DIR}/Dockerfile" << 'EOF'
FROM seldonio/mlserver:1.7.1-slim

# Install MLFlow runtime and dependencies
RUN pip install mlserver-mlflow scikit-learn

# Copy model files
COPY model /mnt/models/wine-quality-elasticnet

# Set environment variables
ENV MLSERVER_MODELS_DIR=/mnt/models
ENV MLSERVER_HTTP_PORT=8080
ENV MLSERVER_GRPC_PORT=8081

EXPOSE 8080 8081

# Start MLServer
CMD ["mlserver", "start", "/mnt/models"]
EOF

echo "Building Docker image: ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${BUILD_DIR}"

if [ $? -eq 0 ]; then
    echo "✓ Successfully built: ${IMAGE_NAME}"
    echo ""
    echo "Next steps:"
    echo "  1. docker push ${IMAGE_NAME}"
    echo "  2. Update manifests/inference.yaml image to: ${IMAGE_NAME}"
    echo "  3. kubectl delete -f L3_kubernetes_kserve_mlflow/manifests/inference.yaml"
    echo "  4. kubectl apply -f L3_kubernetes_kserve_mlflow/manifests/inference.yaml"
else
    echo "✗ Build failed"
    exit 1
fi
