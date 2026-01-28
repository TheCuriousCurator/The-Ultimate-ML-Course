# Pre-Flight Checklist - KServe on EKS

> **🎉 January 2026 Update:** Setup is now fully automated! LoadBalancers are internet-facing by default, gp3 storage auto-created, and boto3 pre-installed. Just run the scripts in sequence. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md).

Complete this checklist before starting the EKS setup to ensure smooth deployment.

## ✅ AWS Prerequisites

### AWS Account & Credentials

- [ ] AWS account is active and accessible
- [ ] IAM user or role has been created
- [ ] AWS CLI is installed (v2.x or later)
  ```bash
  aws --version  # Should show v2.x
  ```
- [ ] AWS credentials are configured
  ```bash
  aws configure
  # OR verify existing config
  aws sts get-caller-identity
  ```
- [ ] Default region is set (e.g., us-east-1)
  ```bash
  aws configure get region
  ```

### IAM Permissions

Verify your IAM user/role has these permissions:

- [ ] **EKS**: Full access (`eks:*`) or `AmazonEKSClusterPolicy`
- [ ] **EC2**: Full access or managed policies:
  - `AmazonEC2FullAccess`
  - `AmazonVPCFullAccess`
- [ ] **IAM**: Required for creating roles and policies:
  - `iam:CreateRole`
  - `iam:AttachRolePolicy`
  - `iam:CreatePolicy`
  - `iam:PassRole`
- [ ] **CloudFormation**: Full access (used by eksctl)
- [ ] **S3**: Bucket creation and management
- [ ] **ELB/ALB**: Load balancer management

**Quick check:**
```bash
# This should succeed if you have adequate permissions
aws sts get-caller-identity
aws iam list-roles --max-items 1 > /dev/null && echo "IAM access: OK" || echo "IAM access: FAILED"
```

### AWS Service Limits

Check and request increases if needed:

- [ ] **EC2**: At least 3 m5.xlarge instances available in chosen region
  ```bash
  aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=m5.xlarge --region us-east-1 --query "InstanceTypeOfferings[*].Location" --output table
  ```
- [ ] **VPC**: At least 1 VPC available (limit is usually 5)
- [ ] **EIP**: Elastic IP addresses available (need 1 for NAT gateway)
- [ ] **EKS Clusters**: Limit allows creating a new cluster (default: 100)

Check limits in AWS Console: **Service Quotas** → **AWS services**

## ✅ Local Tools Installation

### Required CLI Tools

- [ ] **eksctl** installed (v0.150.0 or later)
  ```bash
  eksctl version
  # Install if missing:
  # curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  # sudo mv /tmp/eksctl /usr/local/bin
  ```

- [ ] **kubectl** installed (v1.28 or later)
  ```bash
  kubectl version --client
  # Install if missing:
  # curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  # sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  ```

- [ ] **Helm** installed (v3.x)
  ```bash
  helm version
  # Install if missing:
  # curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ```

- [ ] **Docker** installed (for building model images)
  ```bash
  docker --version
  ```

- [ ] **jq** installed (optional but helpful)
  ```bash
  jq --version
  # Install if missing: sudo apt-get install jq
  ```

### Verify Tool Functionality

- [ ] Can run eksctl commands:
  ```bash
  eksctl get clusters  # Should return empty list or existing clusters
  ```

- [ ] Can run kubectl commands:
  ```bash
  kubectl version --client
  ```

- [ ] Docker daemon is running:
  ```bash
  docker ps
  ```

## ✅ Network & Connectivity

- [ ] Stable internet connection (cluster creation takes 15-20 minutes)
- [ ] No VPN that might interfere with AWS API calls
- [ ] Firewall allows outbound HTTPS traffic
- [ ] DNS resolution is working:
  ```bash
  nslookup aws.amazon.com
  ```

## ✅ Resource Planning

### Cost Awareness

- [ ] Understand estimated costs (~$560-600/month for default setup)
- [ ] Have budget approval if needed
- [ ] Know how to monitor AWS costs (CloudWatch, Cost Explorer)
- [ ] Plan to use cleanup script when done (to avoid charges)

### Region Selection

- [ ] Chosen AWS region (default: us-east-1)
- [ ] Verify region has adequate capacity
- [ ] Consider proximity to users for latency
- [ ] Check pricing differences between regions

## ✅ MLflow Setup (Optional but Recommended)

If using MLflow for model tracking:

- [ ] MLflow server is running (EC2, local, or will deploy on EKS)
- [ ] MLflow tracking URI is accessible
- [ ] S3 bucket for artifacts (or will create new one)
- [ ] Test MLflow connection:
  ```bash
  export MLFLOW_TRACKING_URI=http://your-mlflow-server:5000
  curl $MLFLOW_TRACKING_URI/health
  ```

## ✅ Code & Configuration

- [ ] Cloned/downloaded this repository
- [ ] Reviewed `eks-cluster-config.yaml`
- [ ] Updated region in config if not using us-east-1
- [ ] Updated instance type if needed (default: m5.xlarge)
- [ ] Scripts have execute permissions:
  ```bash
  chmod +x scripts/*.sh
  ```
- [ ] Docker image is built and pushed (or available in registry):
  ```bash
  docker pull dksahuji/wine-quality-elasticnet-base:3
  ```

## ✅ Knowledge Prerequisites

- [ ] Basic understanding of Kubernetes concepts (pods, services, deployments)
- [ ] Familiar with AWS console navigation
- [ ] Can use command line/terminal
- [ ] Know how to check logs and debug issues
- [ ] Read through EKS_SETUP_GUIDE.md (at least skimmed)

## ✅ Time & Resource Allocation

- [ ] Have 30-40 minutes for initial setup
- [ ] Not under time pressure (in case issues need debugging)
- [ ] Have access to troubleshooting resources
- [ ] Can monitor AWS console during setup

## ✅ Backup & Safety

- [ ] Existing kubectl contexts are backed up (if any):
  ```bash
  cp ~/.kube/config ~/.kube/config.backup
  ```
- [ ] Know how to restore if something goes wrong
- [ ] Understand cleanup procedure (scripts/5-cleanup.sh)
- [ ] Have access to AWS console for manual intervention if needed

## 🚀 Ready to Start?

If all items are checked, you're ready to begin!

```bash
cd scripts
./1-setup-eks-cluster.sh
```

## ❌ If Something is Missing

### Tools Not Installed

See **EKS_SETUP_GUIDE.md** → "Prerequisites" section for detailed installation instructions.

### Insufficient Permissions

Contact your AWS administrator to grant required permissions. Share the IAM permissions list from this checklist.

### Not Sure About Costs

Review the cost estimation section in **EKS_SETUP_GUIDE.md**. Consider:
- Using Spot instances for savings
- Deploying during business hours only
- Running cleanup script after testing

### Network/Connectivity Issues

- Check firewall settings
- Disable VPN temporarily
- Test AWS connectivity: `aws s3 ls`

## 📞 Need Help?

- Review: **EKS_SETUP_GUIDE.md** for detailed instructions
- Debug: **TROUBLESHOOTING.md** for common issues
- Reference: **QUICK_REFERENCE.md** for command cheat sheet

---

**Reminder:** The cluster costs money while running. Use the cleanup script when done:
```bash
cd scripts
./5-cleanup.sh
```

Good luck! 🚀
