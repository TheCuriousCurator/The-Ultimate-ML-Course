# MLflow Configuration for EKS

Guide for setting up and finding your MLflow Tracking URI in EKS environment.

## Three Options for MLflow

### Option 1: Use Existing EC2 MLflow Server (Easiest) ✅

You already have MLflow running on EC2 from the L3 setup.

**Current configuration (from your .env file):**
```bash
MLFLOW_TRACKING_URI=http://ec2-98-81-102-168.compute-1.amazonaws.com:5000
MLFLOW_REGISTRY_URI=http://ec2-98-81-102-168.compute-1.amazonaws.com:5000
```

**Steps to use with EKS:**

1. **Verify MLflow is still running:**
   ```bash
   curl http://ec2-98-81-102-168.compute-1.amazonaws.com:5000/health
   ```

   If not running, SSH to EC2 and start it:
   ```bash
   ssh ubuntu@ec2-98-81-102-168.compute-1.amazonaws.com
   sudo systemctl status mlflow
   sudo systemctl start mlflow  # if not running
   ```

2. **Allow EKS cluster to access EC2 MLflow:**

   Get your EKS VPC CIDR:
   ```bash
   VPC_ID=$(aws eks describe-cluster --name kserve-mlflow-cluster --query "cluster.resourcesVpcConfig.vpcId" --output text)
   VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
   echo "EKS VPC CIDR: $VPC_CIDR"  # Should be 10.0.0.0/16
   ```

   Update EC2 security group:
   ```bash
   # Get EC2 security group ID (from AWS console or)
   EC2_SG_ID="sg-xxxxx"  # Replace with your EC2 security group ID

   # Add inbound rule for EKS
   aws ec2 authorize-security-group-ingress \
     --group-id $EC2_SG_ID \
     --protocol tcp \
     --port 5000 \
     --cidr 10.0.0.0/16 \
     --region us-east-1
   ```

3. **Set environment variables locally:**
   ```bash
   export MLFLOW_TRACKING_URI=http://ec2-98-81-102-168.compute-1.amazonaws.com:5000
   export MLFLOW_REGISTRY_URI=http://ec2-98-81-102-168.compute-1.amazonaws.com:5000
   ```

4. **Test from local machine:**
   ```bash
   python -c "import mlflow; print(mlflow.get_tracking_uri())"
   ```

**Pros:**
- ✅ Already set up and running
- ✅ Persistent across EKS cluster deletions
- ✅ Simple configuration

**Cons:**
- ❌ Single point of failure
- ❌ Not highly available
- ❌ Separate billing for EC2

---

### Option 2: Deploy MLflow on EKS (Recommended for Production) ⭐

Deploy MLflow as a Kubernetes service within your EKS cluster.

**Quick deploy:**
```bash
cd L4_EKS_kserve_mlflow/scripts
./6-deploy-mlflow-on-eks.sh
```

This will:
1. Create a PersistentVolume for MLflow metadata (20GB)
2. Deploy MLflow server with S3 artifact storage
3. Create LoadBalancer service for external access
4. Create ClusterIP service for internal access

**Get the MLflow URL after deployment:**

```bash
# External URL (for your local machine)
MLFLOW_EXTERNAL=$(kubectl get svc mlflow-server -n mlflow-kserve-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "External: http://${MLFLOW_EXTERNAL}:5000"

# Internal URL (for pods in the cluster)
echo "Internal: http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000"
```

**Set environment variables:**

For local development:
```bash
export MLFLOW_TRACKING_URI=http://${MLFLOW_EXTERNAL}:5000
export MLFLOW_REGISTRY_URI=http://${MLFLOW_EXTERNAL}:5000
```

For training pods in the cluster (add to your training pod spec):
```yaml
env:
  - name: MLFLOW_TRACKING_URI
    value: "http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000"
```

**Verify deployment:**
```bash
# Check pods
kubectl get pods -n mlflow-kserve-test -l app=mlflow-server

# Check logs
kubectl logs -f deployment/mlflow-server -n mlflow-kserve-test

# Test health
curl http://${MLFLOW_EXTERNAL}:5000/health
```

**Access MLflow UI:**
```
http://${MLFLOW_EXTERNAL}:5000
```

**Features:**
- ✅ Integrated with EKS cluster
- ✅ Uses S3 for artifacts (via IRSA - no credentials needed)
- ✅ boto3 automatically installed on startup for S3 support
- ✅ Internet-facing LoadBalancer for external access
- ✅ Can scale with cluster
- ✅ Same networking as inference services

**Considerations:**
- ⚠️ Deleted when cluster is deleted (unless you backup data)
- ⚠️ Requires additional resources in cluster
- ⚠️ Container startup takes ~30-40 seconds (boto3 installation)

---

### Option 3: Use Port-Forward (Testing Only) 🔧

If you deployed MLflow on EKS but the LoadBalancer isn't ready yet.

```bash
# Forward MLflow port to localhost
kubectl port-forward -n mlflow-kserve-test svc/mlflow-server 5000:5000

# In another terminal, set URI
export MLFLOW_TRACKING_URI=http://localhost:5000
export MLFLOW_REGISTRY_URI=http://localhost:5000

# Access UI
open http://localhost:5000
```

**Only for:** Local testing, load balancer not ready yet

---

## How to Find Your MLflow URI

### If Using EC2 MLflow:

```bash
# From your .env file
cat L4_EKS_kserve_mlflow/.env | grep MLFLOW_TRACKING_URI
```

### If Deployed on EKS:

```bash
# Get external URL
kubectl get svc mlflow-server -n mlflow-kserve-test

# Look for EXTERNAL-IP column (AWS load balancer hostname)
# Format: http://<EXTERNAL-IP>:5000
```

### Quick Check Script:

```bash
#!/bin/bash
echo "Checking MLflow configurations..."

# Check EC2 (Option 1)
echo -e "\n1. EC2 MLflow:"
if curl -s -o /dev/null -w "%{http_code}" http://ec2-98-81-102-168.compute-1.amazonaws.com:5000/health | grep -q 200; then
    echo "  ✓ Running: http://ec2-98-81-102-168.compute-1.amazonaws.com:5000"
else
    echo "  ✗ Not accessible"
fi

# Check EKS (Option 2)
echo -e "\n2. EKS MLflow:"
if kubectl get deployment mlflow-server -n mlflow-kserve-test &>/dev/null; then
    EXTERNAL=$(kubectl get svc mlflow-server -n mlflow-kserve-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$EXTERNAL" ]; then
        echo "  ✓ Deployed: http://${EXTERNAL}:5000"
    else
        echo "  ⚠ Deployed but LoadBalancer not ready yet"
    fi
else
    echo "  - Not deployed"
fi

# Check current environment
echo -e "\n3. Current environment:"
if [ -n "$MLFLOW_TRACKING_URI" ]; then
    echo "  MLFLOW_TRACKING_URI=$MLFLOW_TRACKING_URI"
else
    echo "  MLFLOW_TRACKING_URI not set"
fi
```

Save as `check-mlflow.sh`, make executable, and run:
```bash
chmod +x check-mlflow.sh
./check-mlflow.sh
```

---

## Configuration in Different Contexts

### 1. Local Training Script

Add to your training script:

```python
import os
import mlflow

# Set tracking URI
MLFLOW_URI = "http://ec2-98-81-102-168.compute-1.amazonaws.com:5000"
# OR if using EKS MLflow:
# MLFLOW_URI = "http://<eks-mlflow-lb>:5000"

mlflow.set_tracking_uri(MLFLOW_URI)
mlflow.set_registry_uri(MLFLOW_URI)

# Verify connection
print(f"MLflow URI: {mlflow.get_tracking_uri()}")

# Start experiment
mlflow.set_experiment("wine-quality")
with mlflow.start_run():
    # Your training code
    pass
```

### 2. Training Pod in EKS

Create a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mlflow-config
  namespace: mlflow-kserve-test
data:
  MLFLOW_TRACKING_URI: "http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000"
  MLFLOW_REGISTRY_URI: "http://mlflow-server-internal.mlflow-kserve-test.svc.cluster.local:5000"
```

Reference in your training pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-job
spec:
  containers:
  - name: trainer
    image: your-training-image:latest
    envFrom:
    - configMapRef:
        name: mlflow-config
```

### 3. CI/CD Pipeline

Add to your GitHub Actions / GitLab CI:

```yaml
env:
  MLFLOW_TRACKING_URI: ${{ secrets.MLFLOW_TRACKING_URI }}
  MLFLOW_REGISTRY_URI: ${{ secrets.MLFLOW_REGISTRY_URI }}

steps:
  - name: Train model
    run: |
      python training_auto-hyperopt.py
```

---

## Troubleshooting

### "Connection refused"

```bash
# Check if MLflow is running
# For EC2:
curl http://ec2-98-81-102-168.compute-1.amazonaws.com:5000/health

# For EKS:
kubectl get pods -n mlflow-kserve-test -l app=mlflow-server
kubectl logs deployment/mlflow-server -n mlflow-kserve-test
```

### "Timeout" from EKS pods

Security group issue:
```bash
# Ensure EC2 security group allows traffic from EKS VPC (10.0.0.0/16)
```

### LoadBalancer pending

```bash
# Check ALB controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check service
kubectl describe svc mlflow-server -n mlflow-kserve-test
```

### Cannot log artifacts to S3

```bash
# Verify service account has S3 access
kubectl describe sa kserve-sa -n mlflow-kserve-test

# Should see annotation: eks.amazonaws.com/role-arn
```

### MLflow URL not accessible from browser

```bash
# Check if LoadBalancer is internet-facing
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'mlflow')].{Scheme:Scheme,DNS:DNSName}" --output table

# If Scheme is "internal", delete and recreate service
kubectl delete svc mlflow-server -n mlflow-kserve-test
kubectl apply -f manifests/mlflow-server.yaml
```

### "No module named 'boto3'" error

```bash
# Check if boto3 was installed
kubectl logs deployment/mlflow-server -n mlflow-kserve-test | grep "Successfully installed"

# Should show: Successfully installed awscli-... boto3-...

# If not, the manifest needs updating or container needs restart
kubectl rollout restart deployment/mlflow-server -n mlflow-kserve-test
```

---

## Summary: Quick Decision Guide

**Use EC2 MLflow if:**
- You already have it running from L3
- You want persistence across EKS cluster deletions
- You prefer simple setup

**Use EKS MLflow if:**
- You want everything in one cluster
- You need high availability (can add replicas)
- You want automatic S3 integration via IRSA

**My recommendation:**
- **Development:** Use existing EC2 MLflow
- **Production:** Deploy MLflow on EKS for better integration

---

## Next Steps

After configuring MLflow:

1. **Test connection:**
   ```bash
   python -c "import mlflow; mlflow.set_tracking_uri('YOUR_URI'); print(mlflow.list_experiments())"
   ```

2. **Run training:**
   ```bash
   export MLFLOW_TRACKING_URI=<your-uri>
   python training_auto-hyperopt.py
   ```

3. **View in UI:**
   ```
   Open http://<your-mlflow-uri>:5000
   ```

4. **Deploy model:**
   ```bash
   kubectl apply -f manifests/inference.yaml
   ```

---

**Last Updated:** January 2025
