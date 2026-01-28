# Serving MLflow Models on Kubernetes with KServe

This guide explains how to deploy MLflow-logged models to Kubernetes using KServe on EKS.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: Using KServe MLflow ServingRuntime (Recommended)](#method-1-using-kserve-mlflow-servingruntime-recommended)
- [Method 2: Using Custom Docker Images](#method-2-using-custom-docker-images)
- [Method 3: Direct MLflow Model URI](#method-3-direct-mlflow-model-uri)
- [Complete Workflow](#complete-workflow)
- [Testing Your Deployed Model](#testing-your-deployed-model)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **MLflow server running on EKS**:
   ```bash
   kubectl get svc mlflow-server -n mlflow-kserve-test
   ```

2. **Set MLflow tracking URI**:
   ```bash
   export MLFLOW_TRACKING_URI=http://<your-mlflow-lb-url>:5000
   export MLFLOW_REGISTRY_URI=http://<your-mlflow-lb-url>:5000
   ```

3. **KServe installed** (done via `scripts/3-install-kserve.sh`)

4. **S3 bucket and IAM configured** (done via `scripts/4-setup-s3-mlflow.sh`)

---

## Method 1: Using KServe MLflow ServingRuntime (Recommended)

This is the simplest method - no Docker image building required. KServe can directly serve models from MLflow.

### Step 1: Train and Log Model to MLflow

```python
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import load_wine

# Set tracking URI
mlflow.set_tracking_uri("http://<your-mlflow-url>:5000")
mlflow.set_experiment("wine-classification")

# Train model
data = load_wine()
X, y = data.data, data.target

with mlflow.start_run(run_name="wine-rf-model"):
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X, y)

    # Log model
    mlflow.sklearn.log_model(
        model,
        artifact_path="model",
        registered_model_name="wine-classifier"
    )

    # Log metrics
    accuracy = model.score(X, y)
    mlflow.log_metric("accuracy", accuracy)

    print(f"Model logged with accuracy: {accuracy}")
```

### Step 2: Get Model URI

**Option A - From MLflow UI:**
1. Open MLflow UI: `http://<your-mlflow-url>:5000`
2. Go to "Models" → "wine-classifier"
3. Copy the model URI (e.g., `models:/wine-classifier/1`)

**Option B - Programmatically:**
```python
import mlflow
from mlflow.tracking import MlflowClient

client = MlflowClient()

# Get latest model version
model_name = "wine-classifier"
latest_version = client.get_latest_versions(model_name, stages=["None"])[0]
model_uri = f"models:/{model_name}/{latest_version.version}"

print(f"Model URI: {model_uri}")
# Output: models:/wine-classifier/1
```

### Step 3: Create InferenceService with MLflow Runtime

Create `manifests/inference-mlflow-runtime.yaml`:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: wine-classifier-mlflow
  namespace: mlflow-kserve-test
  annotations:
    networking.knative.dev/ingress-class: "kourier.ingress.networking.knative.dev"
    autoscaling.knative.dev/minScale: "1"
    autoscaling.knative.dev/maxScale: "3"
spec:
  predictor:
    serviceAccountName: kserve-sa  # For S3 access
    model:
      modelFormat:
        name: mlflow
      storageUri: "s3://kserve-mlflow-artifacts-<account-id>/artifacts/<run-id>/model"
      # Or use MLflow model registry:
      # storageUri: "models:/wine-classifier/1"
      runtime: kserve-mlflowserver
    resources:
      requests:
        memory: "2Gi"
        cpu: "500m"
      limits:
        memory: "4Gi"
        cpu: "1"
```

### Step 4: Deploy

```bash
# Get your S3 bucket name
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}"

# Get the model's S3 path from MLflow UI or API
# Usually: s3://<bucket>/artifacts/<experiment_id>/<run_id>/model

# Update the YAML with your model URI
kubectl apply -f manifests/inference-mlflow-runtime.yaml

# Check status
kubectl get inferenceservice wine-classifier-mlflow -n mlflow-kserve-test
```

### Advantages:
✅ No Docker image building required
✅ Automatic updates when model changes
✅ Uses MLflow's native serving format
✅ Simpler deployment process

---

## Method 2: Using Custom Docker Images

This method packages your model into a Docker image (what you currently have).

### Step 1: Train and Log Model

Same as Method 1 - train and log to MLflow.

### Step 2: Download Model from MLflow

```python
import mlflow
import os

# Set tracking URI
mlflow.set_tracking_uri("http://<your-mlflow-url>:5000")

# Download model
model_name = "wine-classifier"
model_version = "1"
model_uri = f"models:/{model_name}/{model_version}"

# Download to local directory
local_path = mlflow.artifacts.download_artifacts(model_uri)
print(f"Model downloaded to: {local_path}")
```

### Step 3: Create Dockerfile with Model

```dockerfile
FROM ghcr.io/mlflow/mlflow:v2.10.2

# Install additional dependencies
RUN pip install --upgrade boto3 mlserver mlserver-mlflow

# Copy the downloaded model
COPY ./model /opt/ml/model

# Set environment variables
ENV MODEL_PATH=/opt/ml/model
ENV MLSERVER_MODEL_NAME=wine-classifier
ENV MLSERVER_HTTP_PORT=8080

# Expose port
EXPOSE 8080

# Run MLServer
CMD ["mlserver", "start", "/opt/ml/model"]
```

### Step 4: Build and Push Image

```bash
# Build image
docker build -t your-dockerhub-username/wine-classifier:v1 .

# Push to registry
docker push your-dockerhub-username/wine-classifier:v1
```

### Step 5: Deploy to KServe

Use the existing `manifests/inference.yaml`:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: mlflow-wine-classifier
  namespace: mlflow-kserve-test
  annotations:
    networking.knative.dev/ingress-class: "kourier.ingress.networking.knative.dev"
    autoscaling.knative.dev/minScale: "1"
spec:
  predictor:
    serviceAccountName: kserve-sa
    containers:
      - name: mlflow-wine-classifier
        image: your-dockerhub-username/wine-classifier:v1
        ports:
          - containerPort: 8080
            protocol: TCP
        resources:
          requests:
            memory: "2Gi"
            cpu: "400m"
          limits:
            memory: "4Gi"
            cpu: "600m"
```

Deploy:
```bash
kubectl apply -f manifests/inference.yaml
```

### Advantages:
✅ Full control over dependencies
✅ Can pre-process data in container
✅ Version control through Docker tags
✅ Faster cold starts (model already in image)

### Disadvantages:
❌ Need to rebuild image for model updates
❌ Larger image size
❌ More complex CI/CD pipeline

---

## Method 3: Direct MLflow Model URI

Use MLflow's model registry directly with KServe.

### Prerequisites:

1. **Register model in MLflow**:
```python
import mlflow

mlflow.set_tracking_uri("http://<your-mlflow-url>:5000")

# After training
mlflow.sklearn.log_model(
    model,
    artifact_path="model",
    registered_model_name="wine-classifier"
)

# Transition to Production (optional)
client = mlflow.tracking.MlflowClient()
client.transition_model_version_stage(
    name="wine-classifier",
    version=1,
    stage="Production"
)
```

2. **Create InferenceService**:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: wine-classifier-registry
  namespace: mlflow-kserve-test
spec:
  predictor:
    serviceAccountName: kserve-sa
    model:
      modelFormat:
        name: mlflow
      # Use model registry URI
      storageUri: "models:/wine-classifier/Production"
      # Or specific version
      # storageUri: "models:/wine-classifier/1"
      env:
        - name: MLFLOW_TRACKING_URI
          value: "http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000"
```

---

## Complete Workflow

Here's a complete end-to-end workflow:

### 1. Train and Register Model

```python
# training_script.py
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import load_wine
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, f1_score
import pandas as pd

# Configure MLflow
MLFLOW_URI = "http://k8s-mlflowks-mlflowse-287af9fc83-4404313a7c435161.elb.us-east-1.amazonaws.com:5000"
mlflow.set_tracking_uri(MLFLOW_URI)
mlflow.set_experiment("wine-classification")

# Load data
data = load_wine()
X, y = data.data, data.target
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train model
with mlflow.start_run(run_name="wine-rf-production"):
    # Model parameters
    params = {
        "n_estimators": 100,
        "max_depth": 10,
        "random_state": 42
    }

    # Train
    model = RandomForestClassifier(**params)
    model.fit(X_train, y_train)

    # Evaluate
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average='weighted')

    # Log parameters and metrics
    mlflow.log_params(params)
    mlflow.log_metric("accuracy", accuracy)
    mlflow.log_metric("f1_score", f1)

    # Log model with input example
    input_example = pd.DataFrame(X_train[:1], columns=data.feature_names)

    mlflow.sklearn.log_model(
        model,
        artifact_path="model",
        registered_model_name="wine-classifier",
        input_example=input_example
    )

    run_id = mlflow.active_run().info.run_id
    print(f"Model logged! Run ID: {run_id}")
    print(f"Accuracy: {accuracy:.4f}")
    print(f"F1 Score: {f1:.4f}")

# Transition to Production
client = mlflow.tracking.MlflowClient()
latest_version = client.get_latest_versions("wine-classifier", stages=["None"])[0]
client.transition_model_version_stage(
    name="wine-classifier",
    version=latest_version.version,
    stage="Production"
)

print(f"Model version {latest_version.version} moved to Production")
```

### 2. Run Training

```bash
export MLFLOW_TRACKING_URI=http://<your-mlflow-url>:5000
python training_script.py
```

### 3. Get Model Information

```bash
# Get run ID from output or MLflow UI
RUN_ID="<your-run-id>"

# Get S3 path
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}"
MODEL_URI="s3://${BUCKET}/artifacts/${RUN_ID}/model"

echo "Model URI: ${MODEL_URI}"
```

### 4. Create InferenceService YAML

```bash
cat > manifests/inference-mlflow-wine.yaml <<EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: wine-classifier
  namespace: mlflow-kserve-test
  annotations:
    networking.knative.dev/ingress-class: "kourier.ingress.networking.knative.dev"
    autoscaling.knative.dev/minScale: "1"
    autoscaling.knative.dev/maxScale: "5"
spec:
  predictor:
    serviceAccountName: kserve-sa
    model:
      modelFormat:
        name: mlflow
      storageUri: "${MODEL_URI}"
      runtime: kserve-mlflowserver
    resources:
      requests:
        memory: "2Gi"
        cpu: "500m"
      limits:
        memory: "4Gi"
        cpu: "1"
EOF
```

### 5. Deploy to KServe

```bash
kubectl apply -f manifests/inference-mlflow-wine.yaml

# Wait for ready
kubectl wait --for=condition=Ready inferenceservice/wine-classifier -n mlflow-kserve-test --timeout=300s

# Get status
kubectl get inferenceservice wine-classifier -n mlflow-kserve-test
```

---

## Testing Your Deployed Model

### Get the Inference URL

```bash
# Get the external hostname
INGRESS_HOST=$(kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get the service hostname
SERVICE_HOSTNAME=$(kubectl get inferenceservice wine-classifier -n mlflow-kserve-test -o jsonpath='{.status.url}' | sed 's|http://||')

echo "INGRESS_HOST: ${INGRESS_HOST}"
echo "SERVICE_HOSTNAME: ${SERVICE_HOSTNAME}"
```

### Test with curl

```bash
# Create test data
cat > test_data.json <<EOF
{
  "inputs": [
    [13.2, 2.8, 2.9, 29.0, 130.0, 2.8, 3.0, 0.3, 2.4, 5.5, 1.0, 3.4, 1050.0]
  ]
}
EOF

# Test prediction
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @test_data.json \
  http://${INGRESS_HOST}/v2/models/wine-classifier/infer

# Or use MLflow format
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @test_data.json \
  http://${INGRESS_HOST}/invocations
```

### Test with Python

```python
import requests
import json

# Configuration
INGRESS_HOST = "<your-ingress-host>"
SERVICE_HOSTNAME = "<your-service-hostname>"

# Prepare test data
test_data = {
    "inputs": [
        [13.2, 2.8, 2.9, 29.0, 130.0, 2.8, 3.0, 0.3, 2.4, 5.5, 1.0, 3.4, 1050.0]
    ]
}

# Make prediction
headers = {
    "Host": SERVICE_HOSTNAME,
    "Content-Type": "application/json"
}

response = requests.post(
    f"http://{INGRESS_HOST}/v2/models/wine-classifier/infer",
    headers=headers,
    json=test_data
)

print(f"Status: {response.status_code}")
print(f"Prediction: {response.json()}")
```

---

## Troubleshooting

### Model not loading from S3

```bash
# Check pod logs
kubectl logs -n mlflow-kserve-test -l serving.kserve.io/inferenceservice=wine-classifier

# Verify service account has S3 access
kubectl describe sa kserve-sa -n mlflow-kserve-test

# Test S3 access from pod
kubectl exec -it <pod-name> -n mlflow-kserve-test -- aws s3 ls s3://kserve-mlflow-artifacts-<account-id>/
```

### InferenceService not Ready

```bash
# Check status
kubectl describe inferenceservice wine-classifier -n mlflow-kserve-test

# Check events
kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp'

# Check KServe controller logs
kubectl logs -n kserve -l control-plane=kserve-controller-manager
```

### Wrong model version deployed

```bash
# Update the storageUri in the YAML to point to correct version
kubectl edit inferenceservice wine-classifier -n mlflow-kserve-test

# Or delete and redeploy
kubectl delete inferenceservice wine-classifier -n mlflow-kserve-test
kubectl apply -f manifests/inference-mlflow-wine.yaml
```

### MLflow server not accessible from pod

```bash
# Test internal DNS resolution
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000/health

# Check MLflow service
kubectl get svc mlflow-server-internal -n mlflow-kserve-test
```

---

## Comparison of Methods

| Feature | MLflow Runtime | Custom Docker | Model Registry |
|---------|---------------|---------------|----------------|
| **Ease of Setup** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **No Docker Build** | ✅ | ❌ | ✅ |
| **Auto Updates** | ✅ | ❌ | ✅ |
| **Custom Dependencies** | ❌ | ✅ | ❌ |
| **Cold Start Time** | Medium | Fast | Slow |
| **Version Control** | Via S3 URI | Via Docker tag | Via Registry |
| **Best For** | Standard ML models | Complex pipelines | Production models |

---

## Recommended Workflow

**For Development:**
- Use **Method 1 (MLflow Runtime)** for quick iterations
- No Docker building required
- Fast deployment cycle

**For Production:**
- Use **Method 3 (Model Registry)** with MLflow's model versioning
- Promote models through stages (Staging → Production)
- Track model lineage and metrics

**For Complex Use Cases:**
- Use **Method 2 (Custom Docker)** if you need:
  - Custom preprocessing
  - Special dependencies
  - Multi-model ensembles
  - Custom inference logic

---

## Next Steps

1. **Set up CI/CD**: Automate model training → registration → deployment
2. **Monitoring**: Set up model performance monitoring
3. **A/B Testing**: Deploy multiple model versions and split traffic
4. **Model Retraining**: Schedule periodic retraining with new data

---

**Last Updated:** January 2026
**KServe Version:** 0.13
**MLflow Version:** 2.10.2
