# Deployment Workflow - KServe on EKS

> **🎉 January 2026 Update:** Setup is now fully automated! LoadBalancers are internet-facing, gp3 storage auto-created, and boto3 pre-installed. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for details.

Visual guide showing the complete workflow from setup to production deployment.

## Overview Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPLETE DEPLOYMENT WORKFLOW                  │
└─────────────────────────────────────────────────────────────────┘

Phase 1: SETUP (One-time, ~30-35 minutes)
├── 1. Pre-flight checks ✓ PREFLIGHT_CHECKLIST.md
├── 2. Create EKS cluster ⏱ 15-20 min
├── 3. Install ALB Controller ⏱ 5 min
├── 4. Install KServe ⏱ 10 min
└── 5. Setup S3 & IAM ⏱ 2 min

Phase 2: MODEL DEVELOPMENT (Iterative)
├── 1. Train model locally
├── 2. Log to MLflow
├── 3. Register model
└── 4. Build & push Docker image

Phase 3: DEPLOYMENT (Repeatable, ~5 minutes)
├── 1. Update inference.yaml
├── 2. Deploy to KServe
├── 3. Wait for ready
└── 4. Test endpoint

Phase 4: MONITORING (Continuous)
├── Monitor logs
├── Check metrics
└── Scale as needed

Phase 5: CLEANUP (When done)
└── Run cleanup script
```

## Detailed Step-by-Step Workflow

### Phase 1: Infrastructure Setup (First Time Only)

#### Step 1.1: Pre-flight Checks (5 minutes)

```bash
# Follow checklist
open PREFLIGHT_CHECKLIST.md

# Verify AWS access
aws sts get-caller-identity

# Verify tools
eksctl version
kubectl version --client
helm version
```

**Expected Output:** All tools installed, AWS credentials working

#### Step 1.2: Create EKS Cluster (15-20 minutes)

```bash
cd scripts
./1-setup-eks-cluster.sh
```

**What happens:**
1. Validates prerequisites
2. Creates VPC with public/private subnets
3. Creates EKS control plane
4. Creates managed node group with 3 nodes
5. Enables OIDC provider
6. Updates kubeconfig

**Expected Output:**
```
✓ EKS Cluster Setup Complete!
Cluster Name: kserve-mlflow-cluster
Region: us-east-1
```

**Verify:**
```bash
kubectl get nodes
# Should show 3 nodes in Ready state
```

#### Step 1.3: Install AWS Load Balancer Controller (5 minutes)

```bash
./2-setup-alb-controller.sh
```

**What happens:**
1. Creates IAM policy for ALB
2. Creates service account with IAM role
3. Installs cert-manager
4. Installs ALB controller via Helm

**Expected Output:**
```
✓ AWS Load Balancer Controller Setup Complete!
```

**Verify:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
# Should show 2 pods Running
```

#### Step 1.4: Install KServe (10 minutes)

```bash
./3-install-kserve.sh
```

**What happens:**
1. Installs Knative Serving
2. Installs KServe controller
3. Creates mlflow-kserve-test namespace

**Expected Output:**
```
✓ KServe Installation Complete!
```

**Verify:**
```bash
kubectl get pods -n kserve
kubectl get pods -n knative-serving
# All pods should be Running
```

#### Step 1.5: Setup S3 and IAM (2 minutes)

```bash
./4-setup-s3-mlflow.sh
```

**What happens:**
1. Creates S3 bucket for MLflow artifacts
2. Creates IAM policy for S3 access
3. Creates Kubernetes service account with IAM role (IRSA)

**Expected Output:**
```
✓ S3 and IAM Setup Complete!
S3 Bucket: kserve-mlflow-artifacts-123456789
Service Account: kserve-sa
```

**Verify:**
```bash
kubectl get sa kserve-sa -n mlflow-kserve-test
aws s3 ls | grep kserve-mlflow
```

### Phase 2: Model Development (Iterative)

#### Step 2.1: Train Model

```bash
# Set MLflow tracking URI
export MLFLOW_TRACKING_URI=http://your-mlflow-server:5000

# Run training
python training_auto-hyperopt.py
```

**What happens:**
1. Loads wine quality dataset
2. Performs hyperparameter optimization
3. Trains best model
4. Logs metrics and parameters to MLflow

**Expected Output:**
```
Best parameters: {'alpha': 0.5, 'l1_ratio': 0.3}
Model URI: models:/wine-quality-elasticnet/5
```

#### Step 2.2: Build Docker Image (Automated in script)

The training script automatically:
1. Builds Docker image with MLflow model
2. Pushes to Docker registry
3. Registers in MLflow Model Registry

**Manual alternative:**
```bash
mlflow models build-docker \
  -m "models:/wine-quality-elasticnet/5" \
  -n "your-registry/wine-model:v5" \
  --enable-mlserver

docker push your-registry/wine-model:v5
```

### Phase 3: Deployment to KServe (5 minutes)

#### Step 3.1: Update Inference Service YAML

Edit `manifests/inference.yaml`:

```yaml
spec:
  predictor:
    containers:
      - name: "mlflow-wine-classifier"
        image: "your-registry/wine-model:v5"  # Update version
```

#### Step 3.2: Deploy

```bash
cd L4_EKS_kserve_mlflow
kubectl apply -f manifests/inference.yaml
```

**What happens:**
1. KServe creates Knative Service
2. Knative creates pods with your model
3. Service mesh routes traffic
4. Autoscaling configured

#### Step 3.3: Wait for Ready

```bash
kubectl get inferenceservice -n mlflow-kserve-test -w
```

**Expected progression:**
```
NAME                      READY   URL
mlflow-wine-classifier    Unknown
mlflow-wine-classifier    Unknown
mlflow-wine-classifier    True    http://mlflow-wine-classifier...
```

**Or with timeout:**
```bash
kubectl wait --for=condition=Ready \
  inferenceservice/mlflow-wine-classifier \
  -n mlflow-kserve-test \
  --timeout=5m
```

#### Step 3.4: Get Endpoint URL

```bash
# Get the service URL
URL=$(kubectl get inferenceservice mlflow-wine-classifier \
  -n mlflow-kserve-test \
  -o jsonpath='{.status.url}')
echo "Inference URL: $URL"
```

#### Step 3.5: Test Deployment

```bash
# Option 1: Port-forward for local testing
kubectl port-forward -n mlflow-kserve-test \
  svc/mlflow-wine-classifier-predictor-default 8080:80

# Option 2: Use test scripts
./test_inference-mlserver.sh  # V2 protocol
./test_inference.sh           # MLflow endpoint
```

**Expected Output:**
```json
{
  "predictions": [6.2]
}
```

### Phase 4: Monitoring and Operations

#### Check Pod Status

```bash
# List pods
kubectl get pods -n mlflow-kserve-test

# Get pod details
POD=$(kubectl get pods -n mlflow-kserve-test \
  -l serving.kserve.io/inferenceservice=mlflow-wine-classifier \
  -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $POD -n mlflow-kserve-test
```

#### View Logs

```bash
# Current logs
kubectl logs $POD -n mlflow-kserve-test

# Follow logs
kubectl logs -f $POD -n mlflow-kserve-test

# Last 100 lines
kubectl logs --tail=100 $POD -n mlflow-kserve-test
```

#### Monitor Resources

```bash
# Pod resource usage
kubectl top pod -n mlflow-kserve-test

# Node resource usage
kubectl top nodes

# Autoscaling status
kubectl get hpa -n mlflow-kserve-test
```

#### Check Events

```bash
# Recent events
kubectl get events -n mlflow-kserve-test \
  --sort-by='.lastTimestamp' | tail -20

# Watch events
kubectl get events -n mlflow-kserve-test -w
```

### Phase 5: Updates and Rollbacks

#### Rolling Update (Zero Downtime)

```bash
# Update image in inference.yaml
# Then apply
kubectl apply -f manifests/inference.yaml

# Watch rollout
kubectl get pods -n mlflow-kserve-test -w
```

KServe automatically:
1. Creates new pods with new version
2. Waits for health checks
3. Routes traffic to new version
4. Removes old pods

#### Rollback

```bash
# View revision history (if using Deployments)
kubectl rollout history deployment -n mlflow-kserve-test

# Rollback to previous version
kubectl rollout undo deployment <deployment-name> -n mlflow-kserve-test

# Or delete and reapply old inference.yaml
kubectl delete inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
kubectl apply -f manifests/inference.yaml.backup
```

### Phase 6: Cleanup

#### Option 1: Automated Cleanup

```bash
cd scripts
./5-cleanup.sh
```

Removes:
- InferenceServices
- Namespace
- EKS cluster
- Optionally: S3 bucket

#### Option 2: Selective Cleanup

```bash
# Just remove inference service
kubectl delete inferenceservice mlflow-wine-classifier -n mlflow-kserve-test

# Remove namespace (keeps cluster)
kubectl delete namespace mlflow-kserve-test

# Scale down cluster (keeps cluster but reduces cost)
eksctl scale nodegroup \
  --cluster=kserve-mlflow-cluster \
  --name=kserve-nodegroup \
  --nodes=1
```

## Decision Tree: When to Use Each Phase

```
New to project?
├─ YES → Start with Phase 1 (Setup)
└─ NO
   ├─ Need to update model?
   │  └─ YES → Phase 2 (Development) → Phase 3 (Deploy)
   ├─ Model having issues?
   │  └─ YES → Phase 4 (Monitoring) → Check TROUBLESHOOTING.md
   ├─ Need to scale?
   │  └─ YES → Edit inference.yaml (autoscaling) → Phase 3 (Deploy)
   └─ Done with project?
      └─ YES → Phase 5 (Cleanup)
```

## Common Workflows

### Daily Development Workflow

```bash
# 1. Make model changes
vim training_auto-hyperopt.py

# 2. Train new version
python training_auto-hyperopt.py
# Note the new model version: e.g., v7

# 3. Update deployment
vim manifests/inference.yaml
# Change image tag to v7

# 4. Deploy
kubectl apply -f manifests/inference.yaml

# 5. Test
./test_inference-mlserver.sh

# 6. Monitor
kubectl logs -f $POD -n mlflow-kserve-test
```

### Production Deployment Workflow

```bash
# 1. Test in staging (different namespace)
kubectl create namespace staging
# Deploy to staging
# Test thoroughly

# 2. Promote to production
kubectl apply -f manifests/inference.yaml -n mlflow-kserve-test

# 3. Canary deployment (optional)
# Use KServe's canary feature to gradually shift traffic

# 4. Monitor production
# Setup alerts, dashboards, logging
```

### Troubleshooting Workflow

```bash
# 1. Check high-level status
kubectl get inferenceservice -n mlflow-kserve-test

# 2. If not ready, check pods
kubectl get pods -n mlflow-kserve-test

# 3. Describe problematic pod
kubectl describe pod $POD -n mlflow-kserve-test

# 4. Check logs
kubectl logs $POD -n mlflow-kserve-test

# 5. Check events
kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp'

# 6. Consult troubleshooting guide
open TROUBLESHOOTING.md
```

## Architecture Flow

```
Developer
   │
   ├─► Train Model (Local/MLflow)
   │      │
   │      └─► MLflow Registry
   │             │
   │             └─► Docker Image Build
   │                    │
   └────────────────────┴─► Push to Registry
                             │
                             ▼
                       kubectl apply
                             │
                             ▼
                  ┌──────────────────────┐
                  │   KServe Controller  │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │  Knative Service     │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │   Model Pods (Auto   │
                  │   Scaling)           │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │   AWS ALB            │
                  └──────────┬───────────┘
                             │
                             ▼
                         Internet
                             │
                             ▼
                        End Users
```

## Quick Reference by Task

| Task | Command/File |
|------|--------------|
| Setup everything | `scripts/1-setup-eks-cluster.sh` through `4-setup-s3-mlflow.sh` |
| Train model | `python training_auto-hyperopt.py` |
| Deploy model | `kubectl apply -f manifests/inference.yaml` |
| Test model | `./test_inference-mlserver.sh` |
| Check status | `kubectl get inferenceservice -n mlflow-kserve-test` |
| View logs | `kubectl logs -f $POD -n mlflow-kserve-test` |
| Cleanup | `scripts/5-cleanup.sh` |
| Troubleshoot | `TROUBLESHOOTING.md` |
| Quick commands | `QUICK_REFERENCE.md` |

---

**Next Steps:**
1. If setting up for first time → Start with Phase 1
2. If deploying a model → Go to Phase 3
3. If issues → Check `TROUBLESHOOTING.md`
4. For daily operations → Bookmark `QUICK_REFERENCE.md`
