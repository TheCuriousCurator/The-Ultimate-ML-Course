# Key Changes Summary - January 2026

## ⚠️ IMPORTANT: Read This First

This document summarizes critical changes to the EKS KServe MLflow setup. **All issues are now automatically fixed by the setup scripts.**

---

## 🔄 What Changed

### 1. LoadBalancers Are Now Internet-Facing by Default

**Previous Behavior:**
- Both MLflow and Kourier LoadBalancers were created as `internal` (private)
- Services were only accessible from within the VPC
- Required manual intervention to make them public

**New Behavior:**
✅ **Fully Automated** - Scripts now automatically create internet-facing LoadBalancers
- `scripts/3-install-kserve.sh` → Auto-configures Kourier as internet-facing
- `scripts/5-deploy-mlflow-on-eks.sh` → Auto-configures MLflow as internet-facing
- Services are publicly accessible immediately after deployment

**Configuration:**
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

---

### 2. gp3 StorageClass Auto-Created

**Previous Behavior:**
- EKS only has `gp2` StorageClass by default
- MLflow PVC would fail with "StorageClass gp3 not found"
- Required manual StorageClass creation

**New Behavior:**
✅ **Fully Automated** - `scripts/5-deploy-mlflow-on-eks.sh` auto-creates gp3
- Checks if gp3 exists before deployment
- Creates gp3 StorageClass if missing
- MLflow deploys successfully with optimized storage

**Benefits:**
- gp3 is more cost-effective than gp2
- Better performance (3000 IOPS, 125 MB/s throughput)
- Same workflow, zero manual steps

---

### 3. boto3 Auto-Installed in MLflow

**Previous Behavior:**
- Official MLflow image doesn't include boto3
- S3 artifact storage would fail with "ModuleNotFoundError: No module named 'boto3'"
- Required custom Docker image

**New Behavior:**
✅ **Fully Automated** - boto3 installed on container startup
- Container startup command now includes: `pip install --upgrade boto3 awscli mlflow`
- S3 artifact storage works out of the box
- No custom Docker images needed

**Note:** First startup takes ~30-40 seconds for package installation

---

### 4. Correct Hostnames in All Scripts

**Previous Behavior:**
- Scripts used InferenceService URL (without `-predictor`)
- Resulted in 404 errors when calling endpoints
- Required manual hostname correction

**New Behavior:**
✅ **Fully Automated** - All scripts use correct predictor hostname
- `test_inference.sh` → Uses predictor URL
- `test_inference-mlserver.sh` → Uses predictor URL
- `get-inference-url.sh` → Shows correct hostname

**Example:**
```bash
# ❌ Old (doesn't work):
# mlflow-wine-classifier.mlflow-kserve-test.example.com

# ✅ New (works):
# mlflow-wine-classifier-predictor.mlflow-kserve-test.example.com
```

---

### 5. Kourier Namespace Corrected

**Previous Behavior:**
- Scripts looked for Kourier in `knative-serving` namespace
- Would fail to find LoadBalancer URL
- Confusing error messages

**New Behavior:**
✅ **Fully Automated** - Scripts check correct namespace
- Primary: `kourier-system` (where Kourier actually is)
- Fallback: `knative-serving` (for other setups)
- Clear error messages if not found

---

## 📋 Verification Checklist

After running the setup, verify everything is configured correctly:

```bash
# 1. Check gp3 StorageClass exists
kubectl get storageclass gp3
# Expected: gp3   ebs.csi.aws.com   Delete   WaitForFirstConsumer   true

# 2. Verify MLflow LoadBalancer is internet-facing
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'mlflow')].{Scheme:Scheme}" \
  --output text
# Expected: internet-facing

# 3. Verify Kourier LoadBalancer is internet-facing
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'kourier')].{Scheme:Scheme}" \
  --output text
# Expected: internet-facing

# 4. Check boto3 is installed in MLflow
kubectl logs deployment/mlflow-server -n mlflow-kserve-test | grep "Successfully installed"
# Expected: Successfully installed awscli-... boto3-... botocore-...

# 5. Test inference endpoint
./test_inference.sh
# Expected: ✓ Success! HTTP Status: 200
```

---

## 🎯 What This Means For You

### If You're Setting Up Fresh:
✅ **Just run the scripts** - Everything works automatically
- No manual configuration needed
- No troubleshooting required
- All services publicly accessible
- S3 integration works immediately

### If You Have an Existing Deployment:
📋 **Migration Steps:**

```bash
# Step 1: Update Kourier LoadBalancer
kubectl delete svc kourier -n kourier-system
kubectl apply -f manifests/kourier-service.yaml

# Step 2: Update MLflow LoadBalancer
kubectl delete svc mlflow-server -n mlflow-kserve-test
kubectl delete deployment mlflow-server -n mlflow-kserve-test
kubectl apply -f manifests/mlflow-server.yaml

# Step 3: Verify everything works
./test_inference.sh
```

---

## 📝 Updated Files Reference

### Scripts:
- `scripts/3-install-kserve.sh` - Auto-configures Kourier
- `scripts/5-deploy-mlflow-on-eks.sh` - Auto-creates gp3, installs boto3
- `scripts/0-cleanup-failed-install.sh` - Removes custom resources
- `scripts/6-cleanup.sh` - Properly deletes all LoadBalancers
- `test_inference.sh` - Uses correct hostname
- `test_inference-mlserver.sh` - Uses correct hostname
- `get-inference-url.sh` - Shows correct URLs and troubleshooting

### Manifests:
- `manifests/kourier-service.yaml` - Internet-facing Kourier (NEW)
- `manifests/storageclass-gp3.yaml` - gp3 definition (NEW)
- `manifests/mlflow-server.yaml` - Internet-facing + boto3

### Documentation:
- `TROUBLESHOOTING.md` - Added 4 new common issues
- `MLFLOW_CONFIGURATION.md` - Added troubleshooting sections
- `SERVING_MLFLOW_MODELS.md` - Complete serving guide (NEW)
- `RECENT_UPDATES.md` - Detailed changelog (NEW)
- `KEY_CHANGES_SUMMARY.md` - This file (NEW)

---

## 💡 Key Takeaways

1. **Everything is automated** - No manual configuration needed
2. **Public by default** - All services are internet-facing
3. **Storage optimized** - Using cost-effective gp3 volumes
4. **S3-ready** - boto3 pre-installed for artifact storage
5. **Works out-of-the-box** - Test scripts just work

---

## 🔗 Related Documentation

- **New User?** → Start with [readme.md](readme.md)
- **Deploying Models?** → See [SERVING_MLFLOW_MODELS.md](SERVING_MLFLOW_MODELS.md)
- **Having Issues?** → Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Detailed Changes?** → Read [RECENT_UPDATES.md](RECENT_UPDATES.md)

---

**Last Updated:** January 28, 2026
**Status:** All automations active ✅
