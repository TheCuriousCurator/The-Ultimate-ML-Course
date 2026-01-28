# Accessing Services on EKS

> **🎉 January 2026 Update:** LoadBalancers are now internet-facing by default! No manual configuration needed. Services are publicly accessible immediately after deployment. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for all automation improvements.

Understanding how to access your inference service on Amazon EKS.

## 🎯 Key Concept: EKS is Cloud-Hosted, Not Local

Unlike Minikube (which runs locally), your EKS cluster runs in AWS cloud. This means:

❌ **NOT accessible via `localhost`** (unless using port-forward)
✅ **Accessible via AWS Load Balancer URL** (production method)

## 📊 Access Methods Comparison

| Method | When to Use | Speed | Production Ready | Cost |
|--------|-------------|-------|------------------|------|
| **External Load Balancer** | Production access | Fast | ✅ Yes | ~$22/mo (ALB) |
| **Port-Forward** | Local testing/debugging | Medium | ❌ No | Free |
| **Ingress (ALB)** | Custom domains | Fast | ✅ Yes | ~$22/mo (ALB) |
| **API Gateway** | Advanced features | Medium | ✅ Yes | Variable |

## 🚀 Method 1: External Load Balancer (Recommended for Production)

This is the **primary method** for accessing services on EKS.

### How It Works

```
Internet → AWS Load Balancer → Knative/Istio Gateway → KServe Pod
         (External DNS)        (Internal routing)
```

### Step 1: Get the External URL

```bash
# Use the helper script
cd L4_EKS_kserve_mlflow
./scripts/get-inference-url.sh
```

This will show:
```
✓ External endpoint: a1234567890abcdef.us-east-1.elb.amazonaws.com
✓ Host Header: mlflow-wine-classifier.mlflow-kserve-test.example.com
```

### Step 2: Test the Service

**Option A: With Host Header (Required)**
```bash
# Get values from previous step
INGRESS_HOST="a1234567890abcdef.us-east-1.elb.amazonaws.com"
SERVICE_HOSTNAME="mlflow-wine-classifier.mlflow-kserve-test.example.com"

# MLflow endpoint
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @test/input_invocations.json \
  http://${INGRESS_HOST}/invocations

# V2 protocol
curl -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @test/input.json \
  http://${INGRESS_HOST}/v2/models/wine-quality-elasticnet/infer
```

**Option B: Add to /etc/hosts (Easier)**
```bash
# Add this line to /etc/hosts
echo "$INGRESS_HOST $SERVICE_HOSTNAME" | sudo tee -a /etc/hosts

# Now you can use the hostname directly
curl -H "Content-Type: application/json" \
  -d @test/input_invocations.json \
  http://${SERVICE_HOSTNAME}/invocations
```

### Step 3: Use in Your Application

**Python Example:**
```python
import requests

INGRESS_HOST = "a1234567890abcdef.us-east-1.elb.amazonaws.com"
SERVICE_HOSTNAME = "mlflow-wine-classifier.mlflow-kserve-test.example.com"

headers = {
    "Host": SERVICE_HOSTNAME,
    "Content-Type": "application/json"
}

data = {
    "dataframe_split": {
        "columns": ["fixed_acidity", "volatile_acidity", ...],
        "data": [[14.23, 1.71, 2.43, ...]]
    }
}

response = requests.post(
    f"http://{INGRESS_HOST}/invocations",
    headers=headers,
    json=data
)

print(response.json())
```

**JavaScript/Node.js Example:**
```javascript
const axios = require('axios');

const INGRESS_HOST = "a1234567890abcdef.us-east-1.elb.amazonaws.com";
const SERVICE_HOSTNAME = "mlflow-wine-classifier.mlflow-kserve-test.example.com";

const response = await axios.post(
  `http://${INGRESS_HOST}/invocations`,
  {
    dataframe_split: {
      columns: ["fixed_acidity", "volatile_acidity", ...],
      data: [[14.23, 1.71, 2.43, ...]]
    }
  },
  {
    headers: {
      'Host': SERVICE_HOSTNAME,
      'Content-Type': 'application/json'
    }
  }
);

console.log(response.data);
```

### Troubleshooting External Access

**Issue: "Connection refused" or timeout**
```bash
# 1. Check if load balancer is provisioned (takes 2-3 minutes)
kubectl get svc -n knative-serving kourier

# Look for EXTERNAL-IP (not <pending>)
# If still pending, wait a few more minutes

# 2. Check security groups
aws elbv2 describe-load-balancers --region us-east-1 | grep DNSName

# 3. Verify InferenceService is ready
kubectl get inferenceservice -n mlflow-kserve-test
```

**Issue: "404 Not Found"**
```bash
# Ensure you're using the correct Host header
# The Host header must match the InferenceService URL

kubectl get inferenceservice mlflow-wine-classifier \
  -n mlflow-kserve-test \
  -o jsonpath='{.status.url}'
```

## 🔧 Method 2: Port-Forward (For Local Testing Only)

Port-forward tunnels traffic from your local machine to the cluster. Use for:
- ✅ Quick testing during development
- ✅ Debugging issues
- ✅ When load balancer is not yet ready

❌ **DO NOT use in production** - it's not stable, not scalable, and requires your machine to be connected.

### How It Works

```
Your Machine (localhost:8080) → Port-Forward Tunnel → KServe Pod
```

### Step 1: Start Port-Forward

```bash
# In a separate terminal (keep it running)
kubectl port-forward -n mlflow-kserve-test \
  svc/mlflow-wine-classifier-predictor-default 8080:80
```

Output:
```
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

### Step 2: Test Locally

```bash
# In another terminal
# MLflow endpoint
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d @test/input_invocations.json

# V2 protocol
curl -X POST http://localhost:8080/v2/models/wine-quality-elasticnet/infer \
  -H "Content-Type: application/json" \
  -d @test/input.json
```

### Step 3: Stop Port-Forward

Press `Ctrl+C` in the terminal running port-forward.

## 🌐 Method 3: Custom Domain with Route53 (Production)

For production, use a custom domain instead of the AWS load balancer DNS.

### Prerequisites
- Domain registered in Route53
- SSL certificate in ACM

### Step 1: Create Route53 Record

```bash
# Get load balancer DNS
LB_DNS=$(kubectl get svc -n knative-serving kourier \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create A record (alias) in Route53 pointing to load balancer
# Via AWS Console or CLI:
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "ml-api.yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "LOAD_BALANCER_ZONE_ID",
          "DNSName": "'$LB_DNS'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

### Step 2: Enable HTTPS

Update `manifests/ingress-alb.yaml`:

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
```

### Step 3: Access via Custom Domain

```bash
curl https://ml-api.yourdomain.com/invocations \
  -H "Content-Type: application/json" \
  -d @test/input_invocations.json
```

## 📱 Method 4: API Gateway (Advanced)

For advanced features like:
- API keys and rate limiting
- Request/response transformation
- Caching
- Usage plans

### Architecture

```
Client → API Gateway → VPC Link → ALB → KServe
```

See AWS API Gateway documentation for setup details.

## 🔍 Quick Reference: Which Method to Use?

### Use **External Load Balancer** when:
- ✅ Deploying to production
- ✅ Need stable, scalable access
- ✅ Accessing from other services/applications
- ✅ Running automated tests against EKS

### Use **Port-Forward** when:
- ✅ Quick local testing during development
- ✅ Debugging issues
- ✅ Load balancer is not yet ready
- ❌ **Never in production!**

### Use **Custom Domain** when:
- ✅ Need branded URL
- ✅ Require HTTPS/SSL
- ✅ Production deployment
- ✅ Multiple environments (dev, staging, prod)

## 🛠️ Helper Scripts

All test scripts automatically handle both methods:

```bash
# These scripts will:
# 1. Try external load balancer first (recommended)
# 2. Fall back to port-forward if LB not ready

./test_inference.sh           # MLflow endpoint
./test_inference-mlserver.sh  # V2 protocol

# Get just the URL info
./scripts/get-inference-url.sh
```

## 🚨 Common Mistakes

### ❌ Using localhost without port-forward
```bash
# This will NOT work on EKS!
curl http://localhost:8080/invocations
# Error: Connection refused
```

### ✅ Correct approach
```bash
# Get external URL first
./scripts/get-inference-url.sh

# Then use external endpoint
curl -H "Host: SERVICE_HOSTNAME" http://INGRESS_HOST/invocations
```

### ❌ Forgetting Host header
```bash
# This will return 404
curl http://a1234.us-east-1.elb.amazonaws.com/invocations
```

### ✅ Correct approach
```bash
# Always include Host header
curl -H "Host: mlflow-wine-classifier.mlflow-kserve-test.example.com" \
  http://a1234.us-east-1.elb.amazonaws.com/invocations
```

## 📚 Additional Resources

- [KServe Ingress Documentation](https://kserve.github.io/website/docs/serverless/servicemesh/)
- [Knative Serving - External Access](https://knative.dev/docs/serving/services/ingress/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

---

**Quick Test Commands:**

```bash
# Get URL and test in one go
./scripts/get-inference-url.sh && ./test_inference.sh

# Or manually
INGRESS=$(kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
HOSTNAME=$(kubectl get inferenceservice mlflow-wine-classifier -n mlflow-kserve-test -o jsonpath='{.status.url}' | sed 's|http://||')
curl -H "Host: $HOSTNAME" http://$INGRESS/invocations -d @test/input_invocations.json
```
