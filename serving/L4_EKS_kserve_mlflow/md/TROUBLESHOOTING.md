# Troubleshooting Guide - KServe on EKS

This guide covers common issues and their solutions when deploying KServe on Amazon EKS.

## Table of Contents

- [Cluster Creation Issues](#cluster-creation-issues)
- [KServe Installation Issues](#kserve-installation-issues)
- [Inference Service Issues](#inference-service-issues)
- [Networking Issues](#networking-issues)
- [IAM and Permissions Issues](#iam-and-permissions-issues)
- [Resource Issues](#resource-issues)
- [Cleanup Issues](#cleanup-issues)
- [Debugging Commands](#debugging-commands)

## Cluster Creation Issues

### Issue: eksctl command fails with "AccessDenied"

**Symptoms:**
```
Error: checking AWS STS access: operation error STS: GetCallerIdentity
```

**Solutions:**
1. Verify AWS credentials:
   ```bash
   aws sts get-caller-identity
   ```

2. Ensure your IAM user/role has required permissions:
   - `eks:*`
   - `ec2:*`
   - `cloudformation:*`
   - `iam:CreateRole`, `iam:AttachRolePolicy`, etc.

3. Try setting credentials explicitly:
   ```bash
   export AWS_ACCESS_KEY_ID="your-key"
   export AWS_SECRET_ACCESS_KEY="your-secret"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

### Issue: Cluster creation stuck or times out

**Symptoms:**
- eksctl hangs for more than 30 minutes
- CloudFormation stack shows "CREATE_IN_PROGRESS"

**Solutions:**
1. Check CloudFormation in AWS Console:
   - Go to CloudFormation service
   - Look for stack named `eksctl-kserve-mlflow-cluster-*`
   - Check events tab for errors

2. Common causes:
   - **Insufficient capacity:** Try a different availability zone or instance type
   - **VPC limits:** Check if you've hit VPC limits in your region
   - **Service limits:** Request limit increases for EC2, EKS

3. If truly stuck (after 45+ minutes), cancel and retry:
   ```bash
   eksctl delete cluster --name kserve-mlflow-cluster --region us-east-1
   # Wait for complete deletion
   eksctl create cluster -f eks-cluster-config.yaml
   ```

### Issue: "No space left on device" error

**Symptoms:**
```
Error: no space left on device
```

**Solution:**
Increase volume size in `eks-cluster-config.yaml`:
```yaml
managedNodeGroups:
  - name: kserve-nodegroup
    volumeSize: 150  # Increase from 100 to 150
```

## KServe Installation Issues

### Issue: KServe pods stuck in "Pending" state

**Check the pods:**
```bash
kubectl get pods -n kserve
kubectl describe pod <pod-name> -n kserve
```

**Common causes and solutions:**

1. **Insufficient resources:**
   ```bash
   # Check node capacity
   kubectl describe nodes

   # Solution: Add more nodes or reduce resource requests
   eksctl scale nodegroup --cluster=kserve-mlflow-cluster --name=kserve-nodegroup --nodes=4
   ```

2. **Pending PVC:**
   ```bash
   kubectl get pvc -n kserve

   # If EBS CSI driver issue, reinstall addon
   eksctl delete addon --cluster kserve-mlflow-cluster --name aws-ebs-csi-driver
   eksctl create addon --cluster kserve-mlflow-cluster --name aws-ebs-csi-driver --force
   ```

### Issue: MLflow PVC stuck in Pending - StorageClass "gp3" not found

**Symptoms:**
```
Warning  ProvisioningFailed  persistentvolume-controller  storageclass.storage.k8s.io "gp3" not found
```

**Check storage class:**
```bash
kubectl get storageclass
kubectl describe pvc mlflow-pvc -n mlflow-kserve-test
```

**Root Cause:**
EKS clusters come with `gp2` StorageClass by default, but the MLflow manifest requests `gp3` which is more performant and cost-effective but must be created manually.

**Solution 1 - Create gp3 StorageClass (Recommended):**
```bash
# The script now auto-creates gp3 if missing, but you can manually create it:
kubectl apply -f manifests/storageclass-gp3.yaml

# Verify it exists
kubectl get storageclass gp3

# If MLflow deployment already exists, delete and redeploy
kubectl delete deployment mlflow-server -n mlflow-kserve-test
kubectl delete pvc mlflow-pvc -n mlflow-kserve-test
cd scripts
./6-deploy-mlflow-on-eks.sh
```

**Solution 2 - Use existing gp2 (Quick fix):**
```bash
# Edit the manifest to use gp2 instead
sed -i 's/storageClassName: gp3/storageClassName: gp2/g' manifests/mlflow-server.yaml

# Then deploy
kubectl apply -f manifests/mlflow-server.yaml
```

**Note:** The updated `6-deploy-mlflow-on-eks.sh` script now automatically creates the gp3 StorageClass if it doesn't exist, preventing this issue.

### Issue: Knative pods crash looping

**Check logs:**
```bash
kubectl logs -n knative-serving -l app=webhook --tail=100
kubectl logs -n knative-serving -l app=controller --tail=100
```

**Common solutions:**

1. **Webhook certificate issues:**
   ```bash
   # Verify cert-manager is working
   kubectl get pods -n cert-manager

   # Check certificates
   kubectl get certificate -A

   # Restart cert-manager if needed
   kubectl rollout restart deployment -n cert-manager
   ```

2. **Re-run the KServe installation:**
   ```bash
   cd scripts
   ./3-install-kserve.sh
   ```

### Issue: "webhook.cert-manager.io" connection refused

**Symptoms:**
```
Internal error occurred: failed calling webhook
```

**Solution:**
```bash
# Wait for cert-manager to be fully ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# If still failing, reinstall cert-manager
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait and then restart KServe
kubectl rollout restart deployment -n kserve kserve-controller-manager
```

### Issue: MLflow S3 artifacts error - "No module named 'boto3'"

**Symptoms:**
```
ModuleNotFoundError: No module named 'boto3'
Exception on /ajax-api/2.0/mlflow/artifacts/list [GET]
```

**Root Cause:**
The official MLflow Docker image (`ghcr.io/mlflow/mlflow`) doesn't include boto3 by default, which is required for S3 artifact storage.

**Check logs:**
```bash
kubectl logs deployment/mlflow-server -n mlflow-kserve-test | grep boto3
```

**Solution:**
The updated `manifests/mlflow-server.yaml` now automatically installs boto3 on container startup. If you deployed before this fix:

```bash
# Delete and redeploy MLflow
kubectl delete deployment mlflow-server -n mlflow-kserve-test
kubectl apply -f manifests/mlflow-server.yaml

# Or re-run the deployment script
cd scripts
./6-deploy-mlflow-on-eks.sh
```

**Verify boto3 is installed:**
```bash
kubectl logs deployment/mlflow-server -n mlflow-kserve-test --tail=50 | grep "Successfully installed"
# Should show: Successfully installed awscli-... boto3-... botocore-...
```

**Alternative - Use custom image with boto3 pre-installed:**
```yaml
# In mlflow-server.yaml
containers:
  - name: mlflow
    image: your-custom-mlflow-image:latest  # Build with boto3 included
```

**Note:** The container startup takes ~30-40 seconds due to boto3 installation. This is normal on first boot.

## Inference Service Issues

### Issue: InferenceService stuck in "IngressNotConfigured"

**Check status:**
```bash
kubectl get inferenceservice -n mlflow-kserve-test
kubectl describe inferenceservice mlflow-wine-classifier -n mlflow-kserve-test
```

**Solutions:**

1. **Check Knative networking:**
   ```bash
   kubectl get pods -n knative-serving
   kubectl logs -n knative-serving -l app=net-kourier-controller
   ```

2. **Verify service and ingress:**
   ```bash
   kubectl get svc -n mlflow-kserve-test
   kubectl get ingress -n mlflow-kserve-test
   ```

3. **Check for event errors:**
   ```bash
   kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp'
   ```

### Issue: Image pull errors

**Symptoms:**
```
Failed to pull image "dksahuji/wine-quality-elasticnet-base:3": rpc error
```

**Solutions:**

1. **Verify image exists:**
   ```bash
   docker pull dksahuji/wine-quality-elasticnet-base:3
   ```

2. **If using private registry:**
   ```bash
   # Create Docker registry secret
   kubectl create secret docker-registry regcred \
     --docker-server=<your-registry> \
     --docker-username=<username> \
     --docker-password=<password> \
     -n mlflow-kserve-test

   # Add to inference.yaml:
   # spec:
   #   predictor:
   #     imagePullSecrets:
   #       - name: regcred
   ```

3. **Check node's ability to pull:**
   ```bash
   # SSH to node (if possible) and try docker pull
   # Or check containerd logs
   kubectl logs -n kube-system -l k8s-app=kube-proxy
   ```

### Issue: Inference service returns 404 or 503

**Check predictor pod:**
```bash
POD_NAME=$(kubectl get pods -n mlflow-kserve-test -l serving.kserve.io/inferenceservice=mlflow-wine-classifier -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n mlflow-kserve-test $POD_NAME
```

**Solutions:**

1. **Port mismatch:**
   - Ensure containerPort in YAML matches the port your model serves on (usually 8080)

2. **Model not loaded:**
   ```bash
   # Check logs for model loading errors
   kubectl logs -n mlflow-kserve-test $POD_NAME | grep -i "error\|failed"
   ```

3. **Health check failing:**
   ```bash
   # Exec into pod and test locally
   kubectl exec -it -n mlflow-kserve-test $POD_NAME -- curl localhost:8080/v2/health/live
   ```

### Issue: Predictions are incorrect or fail

**Debug the model:**

1. **Test locally first:**
   ```bash
   docker run -p 8080:8080 dksahuji/wine-quality-elasticnet-base:3
   curl -X POST http://localhost:8080/invocations -H 'Content-Type: application/json' -d @test/input.json
   ```

2. **Check model version:**
   ```bash
   # Verify you're using the correct model version from MLflow
   kubectl logs -n mlflow-kserve-test $POD_NAME | grep -i "model\|version"
   ```

3. **Verify input format:**
   - Ensure your test data matches the model's expected input schema
   - Check column names, types, and order

## Networking Issues

### Issue: MLflow URL not accessible from browser - LoadBalancer is internal

**Symptoms:**
- MLflow LoadBalancer URL times out when accessed from browser
- curl shows "Connection timed out"
- AWS console shows LoadBalancer scheme is "internal"

**Check LoadBalancer scheme:**
```bash
# Get the LoadBalancer name
kubectl get svc mlflow-server -n mlflow-kserve-test

# Check if it's internal or internet-facing
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'mlflow')].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName}" \
  --output table
```

**Root Cause:**
By default, Kubernetes creates internal LoadBalancers. The updated manifest now includes annotations to make it internet-facing.

**Solution:**
```bash
# Delete and recreate the service with internet-facing annotation
kubectl delete svc mlflow-server -n mlflow-kserve-test
kubectl apply -f manifests/mlflow-server.yaml

# Wait for new LoadBalancer to be provisioned (1-2 minutes)
kubectl get svc mlflow-server -n mlflow-kserve-test -w
```

**Verify it's now internet-facing:**
```bash
MLFLOW_URL=$(kubectl get svc mlflow-server -n mlflow-kserve-test -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${MLFLOW_URL}:5000/health
# Should return: OK
```

**Note:** The updated `manifests/mlflow-server.yaml` includes:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

### Issue: InferenceService URL not accessible - Kourier LoadBalancer is internal

**Symptoms:**
- InferenceService shows Ready but curl to the service times out
- Getting 404 or connection timeout when testing inference endpoint
- AWS console shows Kourier LoadBalancer scheme is "internal"

**Check LoadBalancer scheme:**
```bash
# Check Kourier service
kubectl get svc kourier -n kourier-system

# Verify it's internet-facing
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'kourier')].{Name:LoadBalancerName,Scheme:Scheme,DNS:DNSName}" \
  --output table
```

**Root Cause:**
By default, Kubernetes creates internal (private) LoadBalancers. For external access to InferenceServices, Kourier must be internet-facing.

**Solution 1 - Automated (during installation):**
The updated `3-install-kserve.sh` script now automatically configures Kourier as internet-facing. If you already ran the script with the old version:

```bash
# Delete existing Kourier service
kubectl delete svc kourier -n kourier-system

# Apply internet-facing configuration
kubectl apply -f manifests/kourier-service.yaml

# Wait for new LoadBalancer (2-3 minutes)
kubectl get svc kourier -n kourier-system -w
```

**Solution 2 - Manual annotation:**
```bash
# Delete and recreate with annotations
kubectl delete svc kourier -n kourier-system
kubectl apply -f manifests/kourier-service.yaml
```

**Verify it works:**
```bash
# Get new LoadBalancer URL
KOURIER_HOST=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get service hostname
SERVICE_HOST=$(kubectl get ksvc <your-service>-predictor -n mlflow-kserve-test -o jsonpath='{.status.url}' | sed 's|http://||')

# Test
curl -H "Host: ${SERVICE_HOST}" http://${KOURIER_HOST}/v2/health/live
```

**Note:** The `kourier-service.yaml` manifest includes:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

### Issue: Cannot access InferenceService from outside cluster

**Check load balancer:**
```bash
kubectl get svc -n istio-system
kubectl get svc -n mlflow-kserve-test
```

**Solutions:**

1. **No external IP assigned:**
   ```bash
   # Check if ALB controller is running
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

   # Check for load balancer events
   kubectl describe svc mlflow-wine-classifier-predictor-default -n mlflow-kserve-test
   ```

2. **Security group blocking traffic:**
   ```bash
   # Get the load balancer security group from AWS Console
   # Ensure it allows inbound HTTP/HTTPS from your IP

   # Or allow from anywhere (not recommended for production):
   aws ec2 authorize-security-group-ingress \
     --group-id <sg-id> \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   ```

3. **Use port-forward for testing:**
   ```bash
   kubectl port-forward -n mlflow-kserve-test svc/mlflow-wine-classifier-predictor-default 8080:80
   # Then access at http://localhost:8080
   ```

### Issue: DNS resolution failures

**Symptoms:**
```
Error: dial tcp: lookup mlflow-server on 10.0.0.10:53: no such host
```

**Solutions:**

1. **Check CoreDNS:**
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

2. **Restart CoreDNS:**
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

3. **Use FQDN:**
   ```bash
   # Instead of: http://mlflow-server:5000
   # Use: http://mlflow-server.mlflow-kserve-test.svc.cluster.local:5000
   ```

## IAM and Permissions Issues

### Issue: "AccessDenied" when accessing S3

**Check IRSA setup:**
```bash
# Verify service account exists
kubectl get sa kserve-sa -n mlflow-kserve-test

# Check if IAM role is annotated
kubectl describe sa kserve-sa -n mlflow-kserve-test | grep Annotations
```

**Solutions:**

1. **Re-create service account:**
   ```bash
   cd scripts
   ./4-setup-s3-mlflow.sh
   ```

2. **Verify IAM role trust relationship:**
   - Go to IAM Console → Roles → KServeS3AccessRole
   - Check "Trust relationships" tab
   - Should have trust policy for OIDC provider

3. **Check pod is using service account:**
   ```bash
   kubectl describe pod $POD_NAME -n mlflow-kserve-test | grep "Service Account"
   ```

4. **Test S3 access from pod:**
   ```bash
   kubectl exec -it $POD_NAME -n mlflow-kserve-test -- aws s3 ls
   ```

### Issue: ALB controller cannot create load balancers

**Check controller logs:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Common issues:**

1. **Missing IAM permissions:**
   - Re-run: `./2-setup-alb-controller.sh`
   - Verify policy is attached to role

2. **Subnet tagging:**
   ```bash
   # Public subnets need tag:
   # kubernetes.io/role/elb = 1

   # Get VPC ID
   VPC_ID=$(aws eks describe-cluster --name kserve-mlflow-cluster --query "cluster.resourcesVpcConfig.vpcId" --output text)

   # List subnets
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"

   # Add tag if missing (for each public subnet)
   aws ec2 create-tags --resources subnet-xxxxx --tags Key=kubernetes.io/role/elb,Value=1
   ```

## Resource Issues

### Issue: Pods evicted due to resource pressure

**Check node resources:**
```bash
kubectl top nodes
kubectl describe node <node-name>
```

**Solutions:**

1. **Scale up cluster:**
   ```bash
   eksctl scale nodegroup --cluster=kserve-mlflow-cluster --name=kserve-nodegroup --nodes=4
   ```

2. **Reduce resource requests:**
   Edit `manifests/inference.yaml`:
   ```yaml
   resources:
     requests:
       memory: "1Gi"  # Reduce from 2Gi
       cpu: "200m"    # Reduce from 400m
   ```

3. **Enable cluster autoscaler:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
   ```

### Issue: Out of memory (OOMKilled)

**Check pod events:**
```bash
kubectl describe pod $POD_NAME -n mlflow-kserve-test
```

**Solutions:**

1. **Increase memory limit:**
   ```yaml
   resources:
     limits:
       memory: "8Gi"  # Increase from 4Gi
   ```

2. **Optimize model:**
   - Use model quantization
   - Reduce batch size
   - Use smaller model variant

## Cleanup Issues

### Issue: Cleanup taking longer than expected (20-40 minutes)

**Symptoms:**
- `6-cleanup.sh` script running for 30+ minutes
- CloudFormation stacks stuck in DELETE_IN_PROGRESS
- Script appears to hang during cluster deletion

**Check progress:**
```bash
# In another terminal, watch CloudFormation stacks
watch -n 10 'aws cloudformation describe-stacks --region us-east-1 --query "Stacks[?contains(StackName, '\''kserve'\'')].{Name:StackName,Status:StackStatus}" --output table'

# Watch EKS cluster deletion
watch -n 10 'eksctl get cluster --name kserve-mlflow-cluster --region us-east-1'

# Check LoadBalancers being deleted
watch -n 10 'aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?contains(LoadBalancerName, '\''kserve'\'') || contains(LoadBalancerName, '\''mlflow'\'')].LoadBalancerName" --output table'
```

**Why it's slow:**
- **LoadBalancers:** Each LoadBalancer takes 5-10 minutes to delete
- **ENIs (Elastic Network Interfaces):** Must detach from VPC before deletion (2-5 minutes)
- **NAT Gateway:** Releasing Elastic IP takes time
- **CloudFormation cascading deletes:** Multiple dependent resources

**Solutions:**

1. **Be patient (recommended):**
   - 20-30 minutes is normal for complete cleanup
   - Script will complete eventually
   - Don't interrupt unless it exceeds 45 minutes

2. **Use enhanced v2.0 script:**
   The updated `6-cleanup.sh` includes:
   - Progress indicators showing real-time countdown
   - Retry logic for transient failures
   - Parallel cleanup (IAM + S3 simultaneous)
   - Pre-flight checks showing estimated time

3. **If stuck beyond 45 minutes, use force mode:**
   ```bash
   # Interrupt current run
   Ctrl+C

   # Re-run with force flag
   cd scripts
   ./6-cleanup.sh --force
   ```

### Issue: "waiter state transitioned to Failure" error during cleanup

**Symptoms:**
```
2026-01-28 21:31:50 [ℹ]  1 error(s) occurred while deleting cluster with nodegroup(s)
2026-01-28 21:31:50 [✖]  waiter state transitioned to Failure
Error: failed to delete cluster with nodegroup(s)
```

**Important:** This error is often **misleading** - the cluster may actually be deleted successfully despite the error message!

**Root Cause:**
- CloudFormation waiter timeout in eksctl
- The deletion operation completes, but CloudFormation's status polling times out
- This is a reporting/timing issue, not an actual deletion failure

**Solutions:**

1. **Verify actual cluster state (don't trust the error):**
   ```bash
   # Check if cluster still exists
   eksctl get cluster --name kserve-mlflow-cluster --region us-east-1

   # If "No clusters found", deletion succeeded despite error!
   ```

2. **Use enhanced cleanup script v2.0:**
   The updated script automatically:
   - Detects "waiter" timeout errors
   - Verifies actual cluster state after deletion
   - Reports success if cluster is actually deleted
   - Retries up to 2 times with exponential backoff

   ```bash
   cd scripts
   ./6-cleanup.sh
   # Script will handle this error automatically
   ```

3. **Manual retry if using old script:**
   ```bash
   # Wait 5 minutes, then check cluster state
   sleep 300
   eksctl get cluster --name kserve-mlflow-cluster --region us-east-1

   # If cluster is gone, continue with other cleanup:
   cd scripts
   # Delete IAM policies manually
   # Delete S3 bucket manually
   ```

**How v2.0 handles this:**
```
Attempt 1:
  eksctl delete cluster ...
  → Error: waiter state transitioned to Failure
  → Detected waiter timeout
  → Verifying actual cluster state...
  → Cluster is actually deleted despite waiter error!
  → ✓ Success!
```

### Issue: Cleanup script fails and resources remain

**Symptoms:**
- Script exits with error
- Resources still visible in AWS Console
- Re-running script shows existing resources

**Solutions:**

1. **Re-run the cleanup script (it's idempotent):**
   ```bash
   cd scripts
   ./6-cleanup.sh
   # Safe to run multiple times - skips already-deleted resources
   ```

2. **Use force mode for stuck resources:**
   ```bash
   ./6-cleanup.sh --force
   # - Auto-confirms all prompts
   # - Enables force deletion of stuck stacks
   # - Useful for recovering from failures
   ```

3. **Manual cleanup of specific resources:**

   **Check for orphaned LoadBalancers:**
   ```bash
   aws elbv2 describe-load-balancers --region us-east-1 \
     --query "LoadBalancers[?contains(LoadBalancerName, 'kserve') || contains(LoadBalancerName, 'mlflow')].{Name:LoadBalancerName,ARN:LoadBalancerArn}" \
     --output table

   # Delete if found
   aws elbv2 delete-load-balancer --load-balancer-arn <arn> --region us-east-1
   ```

   **Check for orphaned Security Groups:**
   ```bash
   aws ec2 describe-security-groups --region us-east-1 \
     --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned" \
     --query "SecurityGroups[].{ID:GroupId,Name:GroupName}" --output table

   # Wait 5 minutes after LB deletion, then delete
   aws ec2 delete-security-group --group-id <sg-id> --region us-east-1
   ```

   **Check for orphaned EBS Volumes:**
   ```bash
   aws ec2 describe-volumes --region us-east-1 \
     --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned" \
     --query "Volumes[].{ID:VolumeId,Size:Size,State:State}" --output table

   # Delete if found
   aws ec2 delete-volume --volume-id <vol-id> --region us-east-1
   ```

### Issue: CloudFormation stack stuck in DELETE_FAILED

**Symptoms:**
- CloudFormation stack shows DELETE_FAILED status
- Stack can't be deleted normally
- Error message about dependent resources

**Check stack status:**
```bash
aws cloudformation describe-stacks --region us-east-1 \
  --query "Stacks[?contains(StackName, 'kserve')].{Name:StackName,Status:StackStatus,StatusReason:StackStatusReason}" \
  --output table

# Check stack events for errors
aws cloudformation describe-stack-events --region us-east-1 \
  --stack-name <stack-name> --max-items 10 --output table
```

**Solutions:**

1. **Use force mode in cleanup script:**
   ```bash
   ./6-cleanup.sh --force
   # This will attempt to delete the stack with retain policy
   ```

2. **Manually force delete the stack:**
   ```bash
   # List all stacks related to cluster
   aws cloudformation list-stacks --region us-east-1 \
     --query "StackSummaries[?contains(StackName, 'kserve') && StackStatus!='DELETE_COMPLETE'].StackName" \
     --output table

   # Force delete each stuck stack
   aws cloudformation delete-stack --stack-name <stack-name> --region us-east-1
   ```

3. **If force delete doesn't work, retain and delete:**
   ```bash
   # This removes the stack from CloudFormation but retains AWS resources
   aws cloudformation delete-stack --stack-name <stack-name> \
     --retain-resources <resource-logical-id> --region us-east-1

   # Then manually delete the retained resources from AWS Console or CLI
   ```

4. **Last resort - delete from AWS Console:**
   - Go to CloudFormation service
   - Select the stuck stack
   - Click "Delete"
   - Check "Retain resources" for problematic resources
   - Manually clean up retained resources afterward

### Issue: "An error occurred (ValidationError) when calling DeleteStack"

**Symptoms:**
```
An error occurred (ValidationError) when calling the DeleteStack operation:
Stack [eksctl-kserve-mlflow-cluster-cluster] does not exist
```

**This is actually good news!** The stack is already deleted.

**Solution:**
- No action needed
- The cleanup script v2.0 handles this gracefully
- Continue with rest of cleanup

### Issue: Orphaned resources after cleanup causing ongoing charges

**Check for orphaned resources:**

```bash
# Run the enhanced cleanup script's orphan detection
cd scripts
./6-cleanup.sh
# At the end, it shows comprehensive orphan report

# Or manually check:

# 1. LoadBalancers
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'kserve') || contains(LoadBalancerName, 'mlflow') || contains(LoadBalancerName, 'kourier')].LoadBalancerName"

# 2. EBS Volumes
aws ec2 describe-volumes --region us-east-1 \
  --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned"

# 3. VPCs
aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=kserve-mlflow-cluster"

# 4. Elastic IPs
aws ec2 describe-addresses --region us-east-1 \
  --query "Addresses[?!AssociationId].{IP:PublicIp,AllocationId:AllocationId}"

# 5. CloudWatch Log Groups
aws logs describe-log-groups --region us-east-1 \
  --log-group-name-prefix "/aws/eks/kserve-mlflow-cluster"
```

**Delete orphaned resources:**

```bash
# LoadBalancers (highest cost)
aws elbv2 delete-load-balancer --load-balancer-arn <arn> --region us-east-1

# Wait 5 minutes for LB deletion to complete
sleep 300

# Security Groups (after LBs are gone)
aws ec2 delete-security-group --group-id <sg-id> --region us-east-1

# EBS Volumes
aws ec2 delete-volume --volume-id <vol-id> --region us-east-1

# Elastic IPs (if not associated)
aws ec2 release-address --allocation-id <alloc-id> --region us-east-1

# CloudWatch Log Groups (optional, low cost)
aws logs delete-log-group --log-group-name <name> --region us-east-1
```

**Prevention:**
The enhanced `6-cleanup.sh` v2.0 includes comprehensive orphan detection at the end. Always review the orphan report before considering cleanup complete.

### Issue: VPC not deleted after cleanup

**Symptoms:**
- Cleanup script completes but VPC remains
- AWS Console shows VPC: `eksctl-<cluster-name>-cluster/VPC`
- Ongoing charges for NAT Gateway, Elastic IPs, etc.

**Check VPC status:**
```bash
# Find the VPC
aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=kserve-mlflow-cluster" \
  --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

# Check dependencies
VPC_ID="vpc-xxxxxxxxx"
aws ec2 describe-subnets --region us-east-1 --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets | length(@)'
aws ec2 describe-nat-gateways --region us-east-1 --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways | length(@)'
aws ec2 describe-internet-gateways --region us-east-1 --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways | length(@)'
```

**Root Cause:**
VPC deletion fails if there are remaining dependencies:
- NAT Gateways still deleting (can take 3-5 minutes)
- Network Interfaces (ENIs) still attached
- Subnets contain resources
- Security groups still in use

**Solution 1 - Re-run cleanup script:**
```bash
# The enhanced v2.0 script includes Phase 4: VPC cleanup
cd scripts
./6-cleanup.sh

# Phase 4 will automatically:
# - Delete NAT gateways and release EIPs
# - Detach and delete Internet gateways
# - Delete network interfaces
# - Delete subnets
# - Delete route tables
# - Delete security groups
# - Delete VPC
```

**Solution 2 - Manual VPC cleanup (if script fails):**

The script will provide ready-to-use commands if VPC deletion fails:

```bash
VPC_ID="vpc-xxxxxxxxx"  # Replace with your VPC ID

# 1. Delete NAT Gateways
aws ec2 describe-nat-gateways --region us-east-1 --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[].NatGatewayId' --output text | \
  xargs -I {} aws ec2 delete-nat-gateway --nat-gateway-id {} --region us-east-1

# Wait for NAT gateways to finish deleting
sleep 120

# 2. Detach and delete Internet Gateways
aws ec2 describe-internet-gateways --region us-east-1 --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text | \
  xargs -I {} bash -c "aws ec2 detach-internet-gateway --internet-gateway-id {} --vpc-id $VPC_ID --region us-east-1 && aws ec2 delete-internet-gateway --internet-gateway-id {} --region us-east-1"

# 3. Delete Network Interfaces (ENIs)
aws ec2 describe-network-interfaces --region us-east-1 --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' --output text | \
  xargs -I {} aws ec2 delete-network-interface --network-interface-id {} --region us-east-1

# 4. Delete Subnets
aws ec2 describe-subnets --region us-east-1 --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text | \
  xargs -I {} aws ec2 delete-subnet --subnet-id {} --region us-east-1

# 5. Delete Route Tables (non-main)
aws ec2 describe-route-tables --region us-east-1 --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text | \
  xargs -I {} aws ec2 delete-route-table --route-table-id {} --region us-east-1

# 6. Delete Security Groups (may need multiple attempts)
for i in 1 2 3; do
  echo "Attempt $i to delete security groups..."
  aws ec2 describe-security-groups --region us-east-1 --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | \
    xargs -I {} aws ec2 delete-security-group --group-id {} --region us-east-1 2>/dev/null || true
  sleep 5
done

# 7. Finally, delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID --region us-east-1

# 8. Release Elastic IPs (check for unattached IPs)
aws ec2 describe-addresses --region us-east-1 --query "Addresses[?!AssociationId].AllocationId" --output text | \
  xargs -I {} aws ec2 release-address --allocation-id {} --region us-east-1
```

**Solution 3 - Delete from AWS Console:**
1. EC2 Console → VPC Dashboard → Your VPCs
2. Select the eksctl VPC
3. Actions → Delete VPC
4. AWS will show all dependencies that need to be deleted first
5. Delete each dependency manually, then delete VPC

**Prevention:**
The enhanced cleanup script v2.0 automatically handles VPC cleanup in Phase 4. If you encounter this issue, you're likely using an older version of the script.

**Cost Impact:**
Orphaned VPCs incur charges for:
- NAT Gateway: $32.40/month per gateway
- Elastic IP (unattached): $3.65/month per IP
- Data processing: $0.045/GB through NAT gateway

### Issue: Cannot re-run cleanup script after interruption

**Symptoms:**
- Interrupted cleanup with Ctrl+C
- Afraid to re-run script
- Uncertain what state resources are in

**Solution:**
The enhanced cleanup script v2.0 is fully idempotent:

```bash
# Safe to run multiple times
cd scripts
./6-cleanup.sh

# Script will:
# - Skip already-deleted resources
# - Report "not found" for deleted items (normal)
# - Only delete resources that still exist
# - Show final state of all resources
```

**Best practice after interruption:**
1. Wait 5 minutes for any in-progress operations to complete
2. Re-run the cleanup script
3. Use `--force` flag if you want non-interactive mode

```bash
# After interruption
sleep 300
cd scripts
./6-cleanup.sh --force  # Auto-confirms, completes cleanup
```

## Debugging Commands

### General Debugging Workflow

```bash
# 1. Check high-level status
kubectl get inferenceservice -n mlflow-kserve-test

# 2. Describe the inference service
kubectl describe inferenceservice mlflow-wine-classifier -n mlflow-kserve-test

# 3. Check pods
kubectl get pods -n mlflow-kserve-test
kubectl describe pod <pod-name> -n mlflow-kserve-test

# 4. Check logs
kubectl logs <pod-name> -n mlflow-kserve-test

# 5. Check events
kubectl get events -n mlflow-kserve-test --sort-by='.lastTimestamp'

# 6. Check services
kubectl get svc -n mlflow-kserve-test

# 7. Check networking
kubectl get ingress -n mlflow-kserve-test
```

### System Health Checks

```bash
# All system pods should be running
kubectl get pods -n kube-system
kubectl get pods -n knative-serving
kubectl get pods -n kserve
kubectl get pods -n cert-manager

# Check controller logs
kubectl logs -n kserve -l control-plane=kserve-controller-manager --tail=100
kubectl logs -n knative-serving -l app=controller --tail=100

# Check for failed pods across all namespaces
kubectl get pods -A | grep -v "Running\|Completed"
```

### Network Debugging

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup mlflow-wine-classifier-predictor-default.mlflow-kserve-test.svc.cluster.local

# Test HTTP connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -v http://mlflow-wine-classifier-predictor-default.mlflow-kserve-test.svc.cluster.local/v2/health/live

# Check iptables rules (if needed)
kubectl exec -it <pod-name> -n mlflow-kserve-test -- iptables -L
```

### AWS Resource Checks

```bash
# Check load balancers
aws elbv2 describe-load-balancers --region us-east-1

# Check target groups
aws elbv2 describe-target-groups --region us-east-1

# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*kserve*" --region us-east-1

# Check EBS volumes
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/kserve-mlflow-cluster,Values=owned" --region us-east-1
```

## Getting Help

If you're still stuck after trying these solutions:

1. **Collect diagnostic information:**
   ```bash
   # Create diagnostic bundle
   kubectl cluster-info dump --output-directory=./cluster-dump

   # Compress it
   tar -czf cluster-dump.tar.gz cluster-dump/
   ```

2. **Check KServe GitHub Issues:**
   - https://github.com/kserve/kserve/issues

3. **EKS Documentation:**
   - https://docs.aws.amazon.com/eks/

4. **Knative Troubleshooting:**
   - https://knative.dev/docs/serving/troubleshooting/

## Common Error Messages and Fixes

| Error Message | Likely Cause | Solution |
|---------------|--------------|----------|
| `ImagePullBackOff` | Image doesn't exist or registry auth failed | Verify image name and add imagePullSecrets if needed |
| `CrashLoopBackOff` | Application crashing on startup | Check pod logs for errors |
| `Pending` | Insufficient resources or PVC not bound | Scale cluster or check storage |
| `FailedScheduling` | No nodes meet pod requirements | Check node selectors and taints |
| `Evicted` | Node ran out of resources | Scale cluster or reduce requests |
| `IngressNotConfigured` | Knative networking issue | Check Kourier/Istio pods |
| `RevisionFailed` | Model failed to load | Check model files and dependencies |
| `webhook connection refused` | cert-manager not ready | Wait or restart cert-manager |
| `storageclass.storage.k8s.io "gp3" not found` | gp3 StorageClass doesn't exist | Create gp3 StorageClass or use gp2 |
| `ModuleNotFoundError: No module named 'boto3'` | MLflow image missing boto3 for S3 | Redeploy with updated manifest |
| `Connection timed out` to MLflow URL | LoadBalancer is internal not public | Delete and recreate service with internet-facing annotation |
| `Connection timed out` to InferenceService | Kourier LoadBalancer is internal | Delete and apply kourier-service.yaml |
| `404` when calling /invocations | Using wrong hostname (missing -predictor) | Use predictor hostname from ksvc |
| `waiter state transitioned to Failure` | CloudFormation waiter timeout (often cluster is actually deleted) | Verify cluster state with `eksctl get cluster`, use enhanced cleanup v2.0 |
| Cleanup taking 30+ minutes | Normal - LoadBalancers, ENIs, NAT Gateway deletion is slow | Be patient, watch CloudFormation stacks, use force mode if stuck beyond 45 min |
| `Stack does not exist` during cleanup | Stack already deleted (good!) | No action needed, continue with rest of cleanup |
| `DELETE_FAILED` CloudFormation stack | Dependent resources blocking deletion | Use `--force` mode or manually delete stack with retain policy |
| VPC remains after cleanup | NAT gateways, ENIs, or other dependencies blocking deletion | Re-run cleanup script v2.0 (has Phase 4 VPC cleanup) or use manual VPC deletion commands |
| Ongoing charges after cleanup | Orphaned NAT Gateway, Elastic IPs, LoadBalancers | Check orphaned resources section of cleanup output, manually delete remaining resources |

---

**Last Updated:** January 28, 2026
