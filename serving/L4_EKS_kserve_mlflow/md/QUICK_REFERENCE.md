# Quick Reference - KServe on EKS

> **🎉 January 2026 Update:** All setup is now fully automated! LoadBalancers are internet-facing by default, gp3 storage auto-created, and boto3 pre-installed. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md).

A cheat sheet for common commands and operations.

## Setup Commands (Run Once)

```bash
# Full setup in sequence
cd scripts
./1-setup-eks-cluster.sh      # 15-20 min
./2-setup-alb-controller.sh   # 5 min
./3-install-kserve.sh         # 10 min
./4-setup-s3-mlflow.sh        # 2 min
```

## Daily Operations

### Deploy Model

```bash
# Deploy or update model
kubectl apply -f manifests/inference.yaml

# Check status
kubectl get inferenceservice -n mlflow-kserve-test

# Watch deployment
kubectl get pods -n mlflow-kserve-test -w
```

### Test Model

```bash
# Port-forward for local testing
kubectl port-forward -n mlflow-kserve-test svc/mlflow-wine-classifier-predictor-default 8080:80

# Test V2 protocol
curl -X POST http://localhost:8080/v2/models/mlflow-wine-classifier/infer \
  -H 'Content-Type: application/json' \
  -d @test/input.json

# Test MLflow endpoint
curl -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d @test/input_invocations.json

# Or use scripts
./test_inference-mlserver.sh
./test_inference.sh
```

### Get Logs

```bash
# Get pod name
POD=$(kubectl get pods -n mlflow-kserve-test -l serving.kserve.io/inferenceservice=mlflow-wine-classifier -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs -n mlflow-kserve-test $POD

# Follow logs
kubectl logs -n mlflow-kserve-test $POD -f

# View previous logs (if crashed)
kubectl logs -n mlflow-kserve-test $POD --previous
```

### Debug Pods

```bash
# Describe pod
kubectl describe pod $POD -n mlflow-kserve-test

# Get pod YAML
kubectl get pod $POD -n mlflow-kserve-test -o yaml

# Exec into pod
kubectl exec -it $POD -n mlflow-kserve-test -- /bin/bash

# Test from inside pod
kubectl exec -it $POD -n mlflow-kserve-test -- curl localhost:8080/v2/health/live
```

### Check Cluster Health

```bash
# Check all system pods
kubectl get pods -A | grep -v "Running\|Completed"

# KServe controller
kubectl logs -n kserve -l control-plane=kserve-controller-manager --tail=50

# Knative
kubectl get pods -n knative-serving

# ALB controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Node resources
kubectl top nodes
kubectl describe nodes
```

### Manage InferenceServices

```bash
# List all inference services
kubectl get inferenceservice -A

# Describe inference service
kubectl describe inferenceservice mlflow-wine-classifier -n mlflow-kserve-test

# Get detailed status
kubectl get inferenceservice mlflow-wine-classifier -n mlflow-kserve-test -o yaml

# Delete inference service
kubectl delete inferenceservice mlflow-wine-classifier -n mlflow-kserve-test

# Scale manually (edit replicas)
kubectl edit inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
```

### Update Cluster Configuration

```bash
# Update kubeconfig
eksctl utils write-kubeconfig --cluster=kserve-mlflow-cluster --region=us-east-1

# Scale node group
eksctl scale nodegroup \
  --cluster=kserve-mlflow-cluster \
  --name=kserve-nodegroup \
  --nodes=4 \
  --region=us-east-1

# View cluster info
eksctl get cluster --name=kserve-mlflow-cluster --region=us-east-1
eksctl get nodegroup --cluster=kserve-mlflow-cluster --region=us-east-1
```

### AWS Resources

```bash
# List load balancers
aws elbv2 describe-load-balancers --region us-east-1 | jq '.LoadBalancers[] | {Name: .LoadBalancerName, DNS: .DNSName}'

# List S3 buckets
aws s3 ls | grep kserve-mlflow

# Check S3 bucket contents
BUCKET_NAME="kserve-mlflow-artifacts-$(aws sts get-caller-identity --query Account --output text)"
aws s3 ls s3://$BUCKET_NAME/

# List EKS clusters
aws eks list-clusters --region us-east-1
```

### Check Events

```bash
# Recent events in namespace
kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp' | tail -20

# Watch events
kubectl get events -n mlflow-kserve-test -w

# All cluster events
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
```

## Training and Deployment Workflow

```bash
# 1. Set MLflow tracking URI
export MLFLOW_TRACKING_URI=http://your-mlflow-server:5000

# 2. Train model
python training_auto-hyperopt.py

# 3. Note the model version from output
# Output will show: "Model version: 5"

# 4. Update manifests/inference.yaml if needed
# Change image tag to match new version

# 5. Build and push Docker image (done in training script)
# Or manually:
# docker build -t your-registry/model:version .
# docker push your-registry/model:version

# 6. Deploy to KServe
kubectl apply -f manifests/inference.yaml

# 7. Wait for ready
kubectl wait --for=condition=Ready inferenceservice/mlflow-wine-classifier -n mlflow-kserve-test --timeout=5m

# 8. Test
./test_inference-mlserver.sh
```

## Common Troubleshooting Commands

```bash
# Restart deployment
kubectl rollout restart deployment -n mlflow-kserve-test

# Delete and recreate pod
kubectl delete pod $POD -n mlflow-kserve-test

# Check image pull status
kubectl describe pod $POD -n mlflow-kserve-test | grep -A 10 "Events:"

# Check service endpoints
kubectl get endpoints -n mlflow-kserve-test

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup mlflow-wine-classifier-predictor-default.mlflow-kserve-test.svc.cluster.local

# Check security groups (from AWS CLI)
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"
```

## Monitoring Queries

```bash
# Pod resource usage
kubectl top pod -n mlflow-kserve-test

# Watch resource usage
watch kubectl top pod -n mlflow-kserve-test

# Node capacity
kubectl describe node | grep -A 5 "Allocated resources"

# Persistent volumes
kubectl get pv,pvc -A

# Check autoscaling
kubectl get hpa -n mlflow-kserve-test
```

## Cleanup Commands

```bash
# Delete inference service only
kubectl delete inferenceservice mlflow-wine-classifier -n mlflow-kserve-test

# Delete namespace (removes all resources in it)
kubectl delete namespace mlflow-kserve-test

# Full cleanup (cluster + resources)
cd scripts
./5-cleanup.sh

# Manual cluster deletion
eksctl delete cluster --name kserve-mlflow-cluster --region us-east-1 --wait

# Clean up S3
BUCKET_NAME="kserve-mlflow-artifacts-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME
```

## Useful kubectl Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kaf='kubectl apply -f'
alias kdel='kubectl delete'

# KServe specific
alias kis='kubectl get inferenceservice -n mlflow-kserve-test'
alias klogs='kubectl logs -n mlflow-kserve-test -l serving.kserve.io/inferenceservice=mlflow-wine-classifier'
alias kpods='kubectl get pods -n mlflow-kserve-test'

# EKS
alias eks-login='eksctl utils write-kubeconfig --cluster=kserve-mlflow-cluster --region=us-east-1'
```

## Environment Variables

```bash
# AWS Configuration
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Cluster Configuration
export CLUSTER_NAME=kserve-mlflow-cluster
export NAMESPACE=mlflow-kserve-test
export INFERENCE_SERVICE=mlflow-wine-classifier

# MLflow
export MLFLOW_TRACKING_URI=http://your-mlflow-server:5000
export MLFLOW_S3_BUCKET=kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}

# Add to ~/.bashrc to persist
echo "export CLUSTER_NAME=kserve-mlflow-cluster" >> ~/.bashrc
```

## Quick Health Check Script

Save as `health-check.sh`:

```bash
#!/bin/bash
echo "=== Cluster Health ==="
kubectl get nodes
echo -e "\n=== System Pods ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get pods -n knative-serving
kubectl get pods -n kserve
echo -e "\n=== Inference Services ==="
kubectl get inferenceservice -n mlflow-kserve-test
echo -e "\n=== Pods ==="
kubectl get pods -n mlflow-kserve-test
echo -e "\n=== Recent Events ==="
kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp' | tail -10
```

Make executable: `chmod +x health-check.sh`

---

**Tip:** Bookmark this page for quick reference during daily operations!
