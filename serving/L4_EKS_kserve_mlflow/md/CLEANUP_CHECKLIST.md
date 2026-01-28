# Cleanup Checklist - Complete Resource Inventory

> **🎉 January 2026 Update:** Cleanup script enhanced to handle gp3 StorageClass and internet-facing LoadBalancers automatically. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for all improvements.

This document lists ALL resources created by the EKS setup scripts and how they are cleaned up.

## Automated Cleanup (via 5-cleanup.sh)

The `5-cleanup.sh` script automatically handles:

### Phase 1: Kubernetes Resources ✅
- [x] InferenceServices (all in mlflow-kserve-test namespace)
- [x] Load Balancer services (Knative, Istio, Kourier)
- [x] mlflow-kserve-test namespace
- [x] Wait for AWS load balancers to be terminated

### Phase 2: IAM Service Accounts ✅
- [x] kserve-sa (in mlflow-kserve-test namespace) + associated IAM role
- [x] aws-load-balancer-controller (in kube-system) + associated IAM role

### Phase 3: EKS Cluster ✅
- [x] EKS cluster deletion (includes):
  - Control plane
  - Node groups
  - VPC and subnets
  - NAT Gateway
  - Internet Gateway
  - Route tables
  - Most security groups
  - CloudFormation stacks

### Phase 4: IAM Policies ✅ (with confirmation)
- [x] KServeS3AccessPolicy (all versions)
- [x] AWSLoadBalancerControllerIAMPolicy (all versions)

### Phase 5: S3 Storage ✅ (with confirmation)
- [x] S3 bucket: kserve-mlflow-artifacts-{ACCOUNT_ID}
- [x] All objects in bucket
- [x] All versions (if versioning enabled)
- [x] All delete markers

### Phase 6: Orphaned Resource Detection ✅
- [x] Detect orphaned load balancers
- [x] Detect orphaned security groups
- [x] Detect orphaned EBS volumes
- [x] Detect CloudWatch log groups
- [x] Provide commands to manually delete if found

## Resources Created by Each Script

### Script 1: setup-eks-cluster.sh

**AWS Resources Created:**
- EKS cluster (managed by eksctl)
- VPC with CIDR 10.0.0.0/16
- Public and private subnets across 3 AZs
- NAT Gateway + Elastic IP
- Internet Gateway
- Route tables
- Security groups for nodes and control plane
- 3x EC2 instances (m5.xlarge)
- 3x EBS volumes (100GB each, gp3)
- OIDC provider for IRSA
- IAM roles for nodes
- CloudFormation stacks (managed by eksctl)

**Cleanup:**
✅ All deleted by `eksctl delete cluster`

### Script 2: setup-alb-controller.sh

**AWS Resources Created:**
- IAM policy: AWSLoadBalancerControllerIAMPolicy
- IAM role for service account (auto-named by eksctl)
- Kubernetes service account: aws-load-balancer-controller (kube-system)
- cert-manager namespace + pods
- ALB controller deployment (kube-system)
- Webhook configurations

**Cleanup:**
✅ IAM service account deleted in Phase 2
✅ IAM policy deleted in Phase 4 (with confirmation)
✅ Kubernetes resources deleted with cluster

### Script 3: install-kserve.sh

**AWS Resources Created:**
- None directly

**Kubernetes Resources Created:**
- knative-serving namespace + all resources
- kourier-system namespace + all resources
- kserve namespace + controller
- ClusterServingRuntimes (sklearn, xgboost, etc.)
- Webhook configurations
- CRDs (Custom Resource Definitions)
- mlflow-kserve-test namespace

**Cleanup:**
✅ All deleted with cluster in Phase 3

### Script 4: setup-s3-mlflow.sh

**AWS Resources Created:**
- S3 bucket: kserve-mlflow-artifacts-{ACCOUNT_ID}
- S3 versioning enabled
- IAM policy: KServeS3AccessPolicy
- IAM role for service account (auto-named by eksctl)
- Kubernetes service account: kserve-sa (mlflow-kserve-test)

**Cleanup:**
✅ IAM service account deleted in Phase 2
✅ IAM policy deleted in Phase 4 (with confirmation)
✅ S3 bucket deleted in Phase 5 (with confirmation)

## Potential Orphaned Resources

These may be left behind if cleanup doesn't complete properly:

### Load Balancers
**Created by:** ALB controller, Kourier service
**Cost:** ~$16-22/month each
**Check:**
```bash
aws elbv2 describe-load-balancers --region us-east-1 | grep kserve
```
**Delete:**
```bash
aws elbv2 delete-load-balancer --load-balancer-arn <arn> --region us-east-1
```

### Security Groups
**Created by:** EKS, ALB controller
**Cost:** Free
**Check:**
```bash
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"
```
**Delete:**
```bash
aws ec2 delete-security-group --group-id <sg-id> --region us-east-1
```

### EBS Volumes
**Created by:** Persistent volume claims
**Cost:** ~$0.08/GB/month
**Check:**
```bash
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"
```
**Delete:**
```bash
aws ec2 delete-volume --volume-id <vol-id> --region us-east-1
```

### CloudWatch Log Groups
**Created by:** EKS cluster logging
**Cost:** $0.50/GB ingested + storage
**Check:**
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/kserve-mlflow-cluster"
```
**Delete:**
```bash
aws logs delete-log-group --log-group-name <name> --region us-east-1
```

### Elastic Network Interfaces (ENIs)
**Created by:** Pods, load balancers
**Cost:** Free (but can prevent deletion of other resources)
**Check:**
```bash
aws ec2 describe-network-interfaces --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"
```
**Usually:** Auto-deleted within 5-10 minutes

## Cleanup Best Practices

### Before Running Cleanup

1. **Export any important data:**
   ```bash
   # Export MLflow data from S3
   aws s3 sync s3://kserve-mlflow-artifacts-{ACCOUNT} ./backup/
   ```

2. **List all inference services:**
   ```bash
   kubectl get inferenceservice -A
   ```

3. **Check for any important logs:**
   ```bash
   kubectl logs -n mlflow-kserve-test <pod-name> > important-logs.txt
   ```

### Running Cleanup

```bash
cd L4_EKS_kserve_mlflow/scripts
./5-cleanup.sh
```

Follow prompts:
- Confirm cluster deletion
- Confirm IAM policy deletion
- Confirm S3 bucket deletion
- Confirm CloudWatch log deletion

### After Cleanup - Verification

1. **Verify cluster is deleted:**
   ```bash
   eksctl get cluster --region us-east-1
   ```

2. **Check for orphaned resources:**
   ```bash
   # Load balancers
   aws elbv2 describe-load-balancers --region us-east-1 | grep kserve

   # Volumes
   aws ec2 describe-volumes --region us-east-1 --filters "Name=status,Values=available"

   # Security groups (may take a few minutes to be deletable)
   aws ec2 describe-security-groups --region us-east-1 | grep kserve
   ```

3. **Check AWS billing:**
   - Go to AWS Console → Billing Dashboard
   - Check "Cost Explorer" for any ongoing charges
   - Set up billing alert if needed

### Manual Cleanup (If Script Fails)

If the automated script fails, clean up manually in this order:

```bash
# 1. Delete InferenceServices
kubectl delete inferenceservice --all -A

# 2. Delete LoadBalancer services
kubectl get svc -A --field-selector spec.type=LoadBalancer
kubectl delete svc <service-name> -n <namespace>

# 3. Delete namespaces
kubectl delete namespace mlflow-kserve-test kserve knative-serving kourier-system cert-manager

# 4. Wait for load balancers to be deleted (check AWS console)
# This can take 5-10 minutes

# 5. Delete cluster
eksctl delete cluster --name kserve-mlflow-cluster --region us-east-1 --wait

# 6. Delete IAM policies
aws iam delete-policy --policy-arn arn:aws:iam::{ACCOUNT}:policy/KServeS3AccessPolicy
aws iam delete-policy --policy-arn arn:aws:iam::{ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy

# 7. Delete S3 bucket
aws s3 rm s3://kserve-mlflow-artifacts-{ACCOUNT} --recursive
aws s3 rb s3://kserve-mlflow-artifacts-{ACCOUNT}

# 8. Check for orphaned resources (see commands above)
```

## Cost After Cleanup

After successful cleanup, you should have:
- $0/month for compute (no EC2 instances)
- $0/month for EKS (no cluster)
- $0/month for load balancers (none running)
- $0/month for storage (no EBS volumes)

**Only potential remaining costs:**
- S3 storage if you kept the bucket
- CloudWatch logs if not deleted

## Troubleshooting Cleanup

### "Cluster not found"
- Already deleted, continue with manual resource checks

### "Failed to delete load balancer"
- May have dependencies, wait 5 minutes and retry
- Check if still attached to target groups

### "Security group in use"
- ENIs may still be attached, wait 5-10 minutes
- Check for dependent security groups

### "Cannot delete policy - attached to role"
- Role may not be deleted yet, wait and retry
- Check for manually created roles

### "Bucket not empty"
- Objects may have been added after script ran
- Manually empty: `aws s3 rm s3://bucket --recursive`
- For versioned buckets, delete all versions

## Emergency Stop

If you need to stop cleanup midway:

1. Press `Ctrl+C`
2. Note which phase was running
3. Resources up to that phase are deleted
4. Re-run script later (it's idempotent)

## Confirmation of Complete Cleanup

Run this verification script:

```bash
#!/bin/bash
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "Checking for remaining resources..."

# Check cluster
eksctl get cluster --name $CLUSTER_NAME --region $REGION 2>&1 | grep -q "No cluster found" && echo "✓ Cluster deleted" || echo "✗ Cluster still exists"

# Check load balancers
aws elbv2 describe-load-balancers --region $REGION 2>&1 | grep -q kserve && echo "✗ Load balancers found" || echo "✓ No load balancers"

# Check S3 bucket
aws s3 ls s3://kserve-mlflow-artifacts-$ACCOUNT 2>&1 | grep -q "NoSuchBucket" && echo "✓ S3 bucket deleted" || echo "✗ S3 bucket exists"

# Check IAM policies
aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT:policy/KServeS3AccessPolicy 2>&1 | grep -q "NoSuchEntity" && echo "✓ KServe policy deleted" || echo "✗ KServe policy exists"

aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT:policy/AWSLoadBalancerControllerIAMPolicy 2>&1 | grep -q "NoSuchEntity" && echo "✓ ALB policy deleted" || echo "✗ ALB policy exists"

echo "Cleanup verification complete!"
```

---

**Last Updated:** January 2025

For questions or issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
