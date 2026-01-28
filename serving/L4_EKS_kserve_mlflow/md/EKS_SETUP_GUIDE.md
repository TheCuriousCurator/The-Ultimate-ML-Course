# KServe on Amazon EKS with MLflow - Complete Setup Guide

This guide provides comprehensive step-by-step instructions for deploying KServe with MLflow on Amazon EKS (Elastic Kubernetes Service).

> **📢 January 2026 Update:** Setup is now fully automated! All LoadBalancers are internet-facing, gp3 auto-created, boto3 pre-installed. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for what's new.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup Steps](#detailed-setup-steps)
- [Deploying Your Model](#deploying-your-model)
- [Testing the Deployment](#testing-the-deployment)
- [Monitoring and Logging](#monitoring-and-logging)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Cost Estimation](#cost-estimation)

## Architecture Overview

The setup includes:
- **EKS Cluster**: Managed Kubernetes cluster on AWS
- **KServe**: Model serving platform with Knative
- **MLflow**: Experiment tracking and model registry
- **AWS Load Balancer Controller**: For external access via ALB
- **S3**: For storing MLflow artifacts and models
- **IAM Roles for Service Accounts (IRSA)**: For secure AWS resource access

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              EKS Cluster                             │   │
│  │  ┌────────────┐  ┌──────────┐  ┌─────────────┐     │   │
│  │  │   KServe   │  │ Knative  │  │ Cert-Manager│     │   │
│  │  └────────────┘  └──────────┘  └─────────────┘     │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │     ML Model Inference Service               │   │   │
│  │  │     (MLflow Wine Classifier)                 │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └────────────┬──────────────────────────────┬──────────┘   │
│               │                              │               │
│  ┌────────────▼──────┐          ┌───────────▼──────────┐   │
│  │   AWS ALB         │          │   S3 Bucket          │   │
│  │   (Load Balancer) │          │   (MLflow Artifacts) │   │
│  └───────────────────┘          └──────────────────────┘   │
│               │                                             │
└───────────────┼─────────────────────────────────────────────┘
                │
        ┌───────▼────────┐
        │   Internet     │
        │   Users/Apps   │
        └────────────────┘
```

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.x or later)
   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install

   # Verify installation
   aws --version
   ```

2. **eksctl** (v0.150.0 or later)
   ```bash
   # Install eksctl
   curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin

   # Verify installation
   eksctl version
   ```

3. **kubectl** (v1.28 or later)
   ```bash
   # Install kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

   # Verify installation
   kubectl version --client
   ```

4. **Helm** (v3.x)
   ```bash
   # Install Helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

   # Verify installation
   helm version
   ```

### AWS Configuration

1. **Configure AWS Credentials**
   ```bash
   aws configure
   ```
   Provide:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., us-east-1)
   - Default output format (json)

2. **Verify AWS Access**
   ```bash
   aws sts get-caller-identity
   ```

### IAM Permissions Required

Your AWS user/role needs the following permissions:
- EKS: Full access to create/manage clusters
- EC2: Full access for VPC, Security Groups, Load Balancers
- IAM: Create/manage roles, policies, and service accounts
- S3: Create/manage buckets
- CloudFormation: Create/manage stacks (used by eksctl)

## Quick Start

If you want to get up and running quickly:

```bash
# Navigate to the scripts directory
cd L4_EKS_kserve_mlflow/scripts

# Run all setup scripts in order
./1-setup-eks-cluster.sh
./2-setup-alb-controller.sh
./3-install-kserve.sh
./4-setup-s3-mlflow.sh

# Deploy your model
cd ..
kubectl apply -f manifests/inference.yaml

# Get the inference service URL
kubectl get inferenceservice -n mlflow-kserve-test
```

Total setup time: **20-30 minutes**

## Detailed Setup Steps

### Step 1: Create EKS Cluster

The cluster configuration is defined in `eks-cluster-config.yaml`.

**Review the configuration:**
```bash
cat eks-cluster-config.yaml
```

**Key configuration details:**
- Cluster name: `kserve-mlflow-cluster`
- Region: `us-east-1` (modify if needed)
- Kubernetes version: 1.31
- Node type: m5.xlarge (4 vCPU, 16GB RAM)
- Node count: 3 (min: 2, max: 4)

**Create the cluster:**
```bash
cd scripts
./1-setup-eks-cluster.sh
```

This script will:
1. Check prerequisites
2. Create the EKS cluster (takes 15-20 minutes)
3. Configure kubectl to connect to the cluster
4. Enable OIDC provider for IAM roles

**Verify the cluster:**
```bash
kubectl get nodes
kubectl cluster-info
```

### Step 2: Install AWS Load Balancer Controller

The ALB controller enables external access to your services.

```bash
./2-setup-alb-controller.sh
```

This script will:
1. Create IAM policy for ALB controller
2. Create IAM service account with the policy
3. Install cert-manager (required dependency)
4. Install AWS Load Balancer Controller via Helm

**Verify the installation:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Step 3: Install KServe

```bash
./3-install-kserve.sh
```

This script will:
1. Install Knative Serving (serverless runtime)
2. Install KServe controller
3. Create `mlflow-kserve-test` namespace for ML workloads

**Verify the installation:**
```bash
# Check Knative Serving
kubectl get pods -n knative-serving

# Check KServe
kubectl get pods -n kserve

# Check namespaces
kubectl get ns | grep -E "knative|kserve|mlflow"
```

### Step 4: Setup S3 and IAM for MLflow

```bash
./4-setup-s3-mlflow.sh
```

This script will:
1. Create S3 bucket for MLflow artifacts
2. Enable versioning on the bucket
3. Create IAM policy for S3 access
4. Create Kubernetes service account with IAM role (IRSA)

**The created service account** (`kserve-sa`) allows KServe pods to access S3 without hardcoded credentials.

### Step 5: Setup MLflow Tracking Server (Optional)

You have two options for the MLflow tracking server:

#### Option A: Use Existing EC2-based MLflow Server

If you already have MLflow running on EC2 (from L3), simply:

1. Ensure the EC2 security group allows inbound traffic from EKS cluster
2. Set the tracking URI in your local environment:
   ```bash
   export MLFLOW_TRACKING_URI=http://ec2-XX-XX-XX-XX.compute-1.amazonaws.com:5000
   ```

#### Option B: Deploy MLflow on EKS

Create a deployment for MLflow on the same EKS cluster:

```yaml
# Save as manifests/mlflow-server.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
  namespace: mlflow-kserve-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-server
  template:
    metadata:
      labels:
        app: mlflow-server
    spec:
      serviceAccountName: kserve-sa
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:v2.9.2
        command: ["mlflow", "server"]
        args:
          - "--host=0.0.0.0"
          - "--port=5000"
          - "--default-artifact-root=s3://BUCKET_NAME/artifacts"
          - "--backend-store-uri=sqlite:///mlflow.db"
        ports:
        - containerPort: 5000
        volumeMounts:
        - name: mlflow-data
          mountPath: /mlflow
      volumes:
      - name: mlflow-data
        persistentVolumeClaim:
          claimName: mlflow-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
  namespace: mlflow-kserve-test
spec:
  type: LoadBalancer
  selector:
    app: mlflow-server
  ports:
  - port: 5000
    targetPort: 5000
```

## Deploying Your Model

### Step 1: Train and Register Model with MLflow

```bash
# Set MLflow tracking URI
export MLFLOW_TRACKING_URI=http://your-mlflow-server:5000

# Run training
python training_auto-hyperopt.py
```

This will:
1. Train the wine quality model
2. Log metrics to MLflow
3. Register the model in MLflow Model Registry
4. Build and push Docker image with the model

### Step 2: Deploy to KServe

```bash
# Apply the inference service
kubectl apply -f manifests/inference.yaml

# Check deployment status
kubectl get inferenceservice -n mlflow-kserve-test

# Watch the pods
kubectl get pods -n mlflow-kserve-test -w
```

**Expected output:**
```
NAME                      READY   URL
mlflow-wine-classifier    True    http://mlflow-wine-classifier.mlflow-kserve-test...
```

### Step 3: Get the Inference Endpoint

```bash
# Get the service URL
kubectl get inferenceservice mlflow-wine-classifier -n mlflow-kserve-test -o jsonpath='{.status.url}'

# Or use port-forward for testing
kubectl port-forward -n mlflow-kserve-test svc/mlflow-wine-classifier-predictor-default 8080:80
```

## Testing the Deployment

### Important: EKS is Cloud-Hosted, Not Local!

Unlike Minikube, your service runs in AWS and is **NOT accessible via `localhost`** directly. You have two options:

1. **External Load Balancer** (Production) - Access via AWS ALB DNS
2. **Port-Forward** (Testing/Debug) - Tunnel to localhost

For complete details, see **[ACCESSING_SERVICES.md](ACCESSING_SERVICES.md)**

### Quick Test: Using Automated Scripts (Recommended)

The test scripts automatically detect and use the correct access method:

```bash
# Test V2 protocol (recommended)
./test_inference-mlserver.sh

# Test MLflow native endpoint
./test_inference.sh
```

These scripts will:
1. Try to get the external AWS Load Balancer URL (production method)
2. Fall back to port-forward if load balancer isn't ready yet

### Manual Testing: Method 1 - External URL (Production)

**Step 1: Get the external endpoint**
```bash
# Use the helper script
./scripts/get-inference-url.sh
```

This outputs something like:
```
✓ External endpoint: a1234567890.us-east-1.elb.amazonaws.com
✓ Host Header: mlflow-wine-classifier.mlflow-kserve-test.example.com
```

**Step 2: Test with external endpoint**
```bash
# Set variables from previous output
INGRESS_HOST="a1234567890.us-east-1.elb.amazonaws.com"
SERVICE_HOSTNAME="mlflow-wine-classifier.mlflow-kserve-test.example.com"

# Test V2 protocol
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H 'Content-Type: application/json' \
  -d @test/input.json \
  http://${INGRESS_HOST}/v2/models/wine-quality-elasticnet/infer

# Test MLflow endpoint
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H 'Content-Type: application/json' \
  -d @test/input_invocations.json \
  http://${INGRESS_HOST}/invocations
```

**Note:** The `-H "Host: ..."` header is **required** for routing to work correctly.

### Manual Testing: Method 2 - Port-Forward (Dev/Debug Only)

Use this if the load balancer isn't ready yet (takes 2-3 minutes to provision).

**Step 1: Start port-forward (in a separate terminal)**
```bash
kubectl port-forward -n mlflow-kserve-test \
  svc/mlflow-wine-classifier-predictor-default 8080:80
```

**Step 2: Test via localhost (in another terminal)**
```bash
# Test V2 protocol
curl -X POST http://localhost:8080/v2/models/wine-quality-elasticnet/infer \
  -H 'Content-Type: application/json' \
  -d @test/input.json

# Test MLflow endpoint
curl -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d @test/input_invocations.json
```

**⚠️ Important:** Port-forward is only for testing. Do NOT use in production!

## Monitoring and Logging

### View KServe Logs

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n mlflow-kserve-test -l serving.kserve.io/inferenceservice=mlflow-wine-classifier -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs -n mlflow-kserve-test $POD_NAME -c kserve-container
```

### Monitor with kubectl

```bash
# Watch inference services
kubectl get inferenceservice -n mlflow-kserve-test -w

# Watch pods
kubectl get pods -n mlflow-kserve-test -w

# Describe inference service
kubectl describe inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
```

### CloudWatch Logs

EKS cluster logs are sent to CloudWatch:

1. Go to AWS Console → CloudWatch → Log groups
2. Look for `/aws/eks/kserve-mlflow-cluster/cluster`

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed troubleshooting guide.

### Quick Checks

1. **Cluster not accessible:**
   ```bash
   eksctl utils write-kubeconfig --cluster=kserve-mlflow-cluster --region=us-east-1
   ```

2. **Pods not starting:**
   ```bash
   kubectl describe pod <pod-name> -n mlflow-kserve-test
   kubectl logs <pod-name> -n mlflow-kserve-test
   ```

3. **InferenceService not ready:**
   ```bash
   kubectl get inferenceservice -n mlflow-kserve-test
   kubectl describe inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
   ```

4. **Check all system components:**
   ```bash
   kubectl get pods -n kube-system
   kubectl get pods -n knative-serving
   kubectl get pods -n kserve
   ```

## Cleanup

### Delete Everything

To completely remove the cluster and all resources:

```bash
cd scripts
./5-cleanup.sh
```

This will:
1. Delete all InferenceServices
2. Delete the namespace
3. Delete the EKS cluster
4. Optionally delete S3 bucket

### Delete Just the Model

```bash
kubectl delete inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
```

### Manual Cleanup (if script fails)

```bash
# Delete cluster
eksctl delete cluster --name kserve-mlflow-cluster --region us-east-1

# Delete S3 bucket
BUCKET_NAME="kserve-mlflow-artifacts-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# Check for remaining resources
aws ec2 describe-load-balancers --region us-east-1
aws ec2 describe-volumes --region us-east-1 --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"
```

## Cost Estimation

Approximate monthly costs (us-east-1):

| Resource | Specification | Estimated Cost |
|----------|--------------|----------------|
| EKS Control Plane | 1 cluster | $73/month |
| EC2 Instances | 3x m5.xlarge | ~$430/month |
| EBS Volumes | 300GB gp3 | ~$24/month |
| Application Load Balancer | 1 ALB | ~$22/month |
| Data Transfer | Varies | ~$10-50/month |
| S3 Storage | <100GB | <$5/month |
| **Total** | | **~$564-604/month** |

**Cost optimization tips:**
1. Use Spot Instances for worker nodes (can save 50-70%)
2. Enable cluster autoscaler to scale down during low usage
3. Use smaller instance types if your models allow (m5.large)
4. Delete the cluster when not in use
5. Use S3 lifecycle policies for old artifacts

## Next Steps

1. **Production Readiness:**
   - Enable HTTPS with ACM certificate
   - Set up monitoring with Prometheus/Grafana
   - Configure autoscaling based on metrics
   - Implement A/B testing with KServe canary deployments

2. **Security Hardening:**
   - Restrict security groups
   - Enable pod security policies
   - Use private endpoints for EKS
   - Rotate credentials regularly

3. **Model Management:**
   - Automate model deployment with CI/CD
   - Set up model monitoring and drift detection
   - Implement model versioning strategy
   - Create rollback procedures

## Additional Resources

- [KServe Documentation](https://kserve.github.io/website/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [Knative Documentation](https://knative.dev/docs/)

## Support

For issues or questions:
1. Check the [TROUBLESHOOTING.md](TROUBLESHOOTING.md) guide
2. Review KServe logs: `kubectl logs -n kserve -l control-plane=kserve-controller-manager`
3. Check AWS service health: https://status.aws.amazon.com/

---

**Last Updated:** January 2025
**KServe Version:** 0.16
**EKS Version:** 1.31
