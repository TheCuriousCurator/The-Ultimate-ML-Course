# KServe on Amazon EKS with MLflow

This directory contains everything you need to deploy KServe with MLflow on Amazon EKS (Elastic Kubernetes Service).

> **🎉 January 2026 Update:** All setup is now fully automated! LoadBalancers are internet-facing by default, gp3 storage auto-created, and boto3 pre-installed. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for details.

## 🚀 Quick Start

For complete setup instructions, see **[EKS_SETUP_GUIDE.md](EKS_SETUP_GUIDE.md)**

### Automated Setup (Recommended)

```bash
# 1. Create EKS cluster (15-20 minutes)
cd scripts
./1-setup-eks-cluster.sh

# 2. Install AWS Load Balancer Controller (5 minutes)
./2-setup-alb-controller.sh

# 3. Install KServe (10 minutes)
./3-install-kserve.sh

# 4. Setup S3 and IAM (2 minutes)
./4-setup-s3-mlflow.sh

# 5. Deploy your model
cd ..
kubectl apply -f manifests/inference.yaml
```

**Total setup time: ~30-35 minutes**

## 📁 Directory Structure

```
L4_EKS_kserve_mlflow/
├── EKS_SETUP_GUIDE.md          # Complete setup guide with detailed instructions
├── TROUBLESHOOTING.md          # Troubleshooting common issues
├── readme.md                   # This file (quick start)
├── eks-cluster-config.yaml     # EKS cluster configuration
├── scripts/
│   ├── 1-setup-eks-cluster.sh  # Creates EKS cluster
│   ├── 2-setup-alb-controller.sh # Installs AWS Load Balancer Controller
│   ├── 3-install-kserve.sh     # Installs KServe and dependencies
│   ├── 4-setup-s3-mlflow.sh    # Sets up S3 and IAM for MLflow
│   └── 5-cleanup.sh            # Cleanup script to delete everything
├── manifests/
│   ├── inference.yaml          # KServe InferenceService definition (EKS-optimized)
│   └── ingress-alb.yaml        # ALB Ingress configuration
├── iam-policies/
│   ├── kserve-s3-policy.json   # IAM policy for KServe S3 access
│   └── mlflow-server-policy.json # IAM policy for MLflow server
├── training_auto-hyperopt.py   # Training script with hyperparameter optimization
├── training_auto.py            # Simple training script
├── test_inference.sh           # Test script for MLflow endpoint
├── test_inference-mlserver.sh  # Test script for V2 protocol
└── test/
    ├── input.json              # Test input for predictions
    └── input_invocations.json  # Test input for MLflow invocations

```

## 📋 Prerequisites

Required tools (install before starting):

- **AWS CLI** v2.x or later
- **eksctl** v0.150.0 or later
- **kubectl** v1.28 or later
- **Helm** v3.x
- **Docker** (for building model images)

AWS Requirements:

- AWS account with appropriate permissions (EKS, EC2, IAM, S3)
- Configured AWS credentials (`aws configure`)

## 🔄 Key Differences from L3 (Minikube)

| Aspect | L3 (Minikube) | L4 (EKS) |
|--------|---------------|----------|
| **Infrastructure** | Local Kubernetes | AWS EKS (Cloud) |
| **Load Balancer** | NodePort/Port-forward | AWS NLB (internet-facing) |
| **Storage** | Local volumes | EBS gp3 (via CSI driver) |
| **IAM** | Not applicable | IRSA for S3 access |
| **Scaling** | Manual | Auto-scaling available |
| **Cost** | Free | ~$560-600/month |
| **Production Ready** | No | Yes |
| **External Access** | Port-forward only | Public LoadBalancers |

## 🎯 What You'll Deploy

- **EKS Cluster**: Managed Kubernetes with 3 nodes (m5.xlarge)
- **KServe**: Model serving platform with Knative serverless
- **Kourier Ingress**: Internet-facing Network Load Balancer (NLB)
- **MLflow**: Model registry and tracking with internet-facing NLB
- **S3 Bucket**: For MLflow artifacts
- **IAM Roles**: Secure access via IRSA (IAM Roles for Service Accounts)
- **Storage**: gp3 EBS volumes (auto-created)

## 📖 Detailed Documentation

- **[EKS_SETUP_GUIDE.md](EKS_SETUP_GUIDE.md)**: Complete setup guide with:
  - Detailed prerequisites
  - Step-by-step instructions
  - Architecture overview
  - Testing procedures
  - Monitoring and logging
  - Cost estimation

- **[ACCESSING_SERVICES.md](ACCESSING_SERVICES.md)**: How to access your models:
  - External Load Balancer (production)
  - Port-forward (testing/debug)
  - Custom domains with Route53
  - Code examples in Python/JavaScript

- **[MLFLOW_CONFIGURATION.md](MLFLOW_CONFIGURATION.md)**: MLflow setup options:
  - Use existing EC2 MLflow server
  - Deploy MLflow on EKS
  - Finding and setting tracking URI
  - Configuration for different contexts

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Solutions for:
  - Cluster creation issues
  - KServe installation problems
  - Networking issues
  - IAM and permissions errors
  - Resource issues

## 🧪 Testing Your Deployment

### Important: EKS Services Are Not on Localhost!

Your service runs in AWS cloud and is accessed via AWS Load Balancer, **not localhost**.

**Get inference URL and access instructions:**
```bash
# Shows complete access information including curl examples
./get-inference-url.sh
# Or: ./scripts/get-inference-url.sh
```

**Quick test (automatic):**
```bash
# These scripts automatically use the correct access method
./test_inference.sh           # MLflow native endpoint
./test_inference-mlserver.sh  # V2 protocol
```

**Manual test with external URL:**
```bash
# Get the load balancer endpoint
INGRESS_HOST=$(kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
HOSTNAME=$(kubectl get inferenceservice mlflow-wine-classifier -n mlflow-kserve-test -o jsonpath='{.status.url}' | sed 's|http://||')
# export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
# Test
curl -H "Host: $HOSTNAME" \
  -H "Content-Type: application/json" \
  -d @test/input_invocations.json \
  http://$INGRESS_HOST/invocations
```

**Port-forward (for local testing/debugging only):**
```bash
kubectl port-forward -n mlflow-kserve-test svc/mlflow-wine-classifier-predictor-default 8080:80
curl -X POST http://localhost:8080/invocations -d @test/input_invocations.json
```

📖 **For complete details on accessing services, see [ACCESSING_SERVICES.md](ACCESSING_SERVICES.md)**

## 🧹 Cleanup

To delete everything:

```bash
cd scripts
./5-cleanup.sh
```

This will:
- Delete all InferenceServices
- Delete the namespace
- Delete the EKS cluster
- Optionally delete S3 bucket

## 💰 Cost Estimation

Approximate monthly costs (us-east-1):

- EKS Control Plane: $73/month
- 3x m5.xlarge instances: ~$430/month
- EBS volumes: ~$24/month
- ALB: ~$22/month
- Data transfer: ~$10-50/month
- **Total: ~$560-600/month**

**Cost optimization tips:**
- Use Spot instances (50-70% savings)
- Scale down when not in use
- Delete cluster when finished

## 🆘 Getting Help

If you encounter issues:

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review logs: `kubectl logs -n kserve -l control-plane=kserve-controller-manager`
3. Check AWS service status: https://status.aws.amazon.com/

## 📚 Additional Resources

- [KServe Documentation](https://kserve.github.io/website/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)

---

## Legacy Documentation (For Reference)

Below are the original L3 (Minikube) instructions for comparison:

<details>
<summary>Click to expand L3 Minikube instructions</summary>

### Local Development Setup

```bash
# basic setup
sudo apt-get install zlib1g-dev libssl-dev libbz2-dev libncursesw5-dev libffi-dev libreadline-dev libsqlite3-dev tk-dev liblzma-dev
curl https://pyenv.run | bash
pip install virtualenv
cd /home/mb600l/.pyenv/plugins/python-build/../.. && git pull && cd -
/home/mb600l/.pyenv/bin/pyenv install --skip-existing  3.12.10
export PATH="$HOME/.pyenv/bin:$PATH"
export MLFLOW_TRACKING_URI=http://localhost:5000
export MLSERVER_HOST=0.0.0.0 MLSERVER_HTTP_PORT=8080

# start mlflowserver and lauch UI
mlflow ui --port 5000

# start mlserver in a new terminal
mlserver start ./L4_EKS_kserve_mlflow

# run training in new terminal
python3 ./L4_EKS_kserve_mlflow/training_auto-hyperopt.py

# push docker to remote repository
docker push dksahuji/wine-quality-elasticnet-base:3
```

### Minikube Setup

```bash
minikube start

# Install KServe
curl -s "https://raw.githubusercontent.com/kserve/kserve/release-0.16/hack/quick_install.sh" | bash

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Create namespace
kubectl create namespace mlflow-kserve-test

# Deploy model
kubectl apply -f ./L4_EKS_kserve_mlflow/manifests/inference.yaml
```

### MLflow on EC2

```bash
# On EC2 instance
sudo apt update
curl -LsSf https://astral.sh/uv/install.sh | sh
mkdir mlflow-test && cd mlflow-test
uv init && uv venv
uv add mlflow awscli boto3
source .venv/bin/activate
aws configure

# Start MLflow
mlflow server -h 0.0.0.0 --default-artifact-root s3://your-bucket --allowed-hosts "*"

# Configure as systemd service
sudo vim /etc/systemd/system/mlflow.service
```

</details>

---

**Last Updated:** January 2025
**KServe Version:** 0.16
**EKS Version:** 1.31