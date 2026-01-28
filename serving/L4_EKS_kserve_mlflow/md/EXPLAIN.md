# Complete Beginner's Guide to All Scripts

> **🎉 January 2026 Update:** All scripts have been enhanced with automation! LoadBalancers are internet-facing by default, gp3 storage auto-created, and boto3 pre-installed in MLflow. See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for what changed.

This document explains **every script** in detail, breaking down **every command** like you're learning for the first time.

## Table of Contents

1. [Overview: What Are We Building?](#overview-what-are-we-building)
2. [Script 0: cleanup-failed-install.sh](#script-0-cleanup-failed-installsh)
3. [Script 1: setup-eks-cluster.sh](#script-1-setup-eks-clustersh)
4. [Script 2: setup-alb-controller.sh](#script-2-setup-alb-controllersh)
5. [Script 3: install-kserve.sh](#script-3-install-kservesh)
6. [Script 4: setup-s3-mlflow.sh](#script-4-setup-s3-mlflowsh)
7. [Script 5: cleanup.sh](#script-5-cleanupsh)
8. [Script 6: deploy-mlflow-on-eks.sh](#script-6-deploy-mlflow-on-ekssh)
9. [Helper: get-inference-url.sh](#helper-get-inference-urlsh)
10. [Common Bash Concepts Explained](#common-bash-concepts-explained)

---

## Overview: What Are We Building?

Think of it like building a restaurant:
- **EKS Cluster** = The building/kitchen
- **Load Balancer** = The front door/entrance
- **KServe** = The chef who cooks (serves models)
- **MLflow** = The recipe book (stores model recipes)
- **S3** = The pantry (stores ingredients/artifacts)

We're setting up a cloud-based system where:
1. You train ML models (create recipes)
2. Store them in MLflow (recipe book)
3. Deploy them to KServe (chef cooks them)
4. Users access via Load Balancer (enter through front door)

---

## Script 0: cleanup-failed-install.sh

### What It Does (In Simple Terms)

Imagine you're building with LEGO blocks but made mistakes. This script **takes apart everything** so you can start fresh.

### When To Use

- Installation failed halfway
- Something went wrong
- You want to start over
- Before trying the setup again

### Line-by-Line Explanation

```bash
#!/bin/bash
```
**What it means:** "This is a bash script" (bash = the language we're writing in)
**Why:** Tells the computer how to run this file

```bash
set -e
```
**What it means:** "Stop immediately if anything goes wrong"
**Why:** If one step fails, don't continue and make things worse
**Analogy:** Like a recipe saying "stop cooking if you burn something"

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
```
**What it means:** Colors for text output
**Why:** Makes errors show in red, success in green
**Example:** Like highlighting important text in a book

```bash
echo -e "${YELLOW}Removing KServe...${NC}"
```
**What it means:** Print yellow text saying "Removing KServe"
- `echo` = print to screen
- `-e` = allow colors
- `${YELLOW}` = use yellow color
- `${NC}` = reset to normal color

```bash
kubectl delete -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml --ignore-not-found=true
```
**What it means:** Remove KServe from Kubernetes
**Breaking it down:**
- `kubectl` = Kubernetes command-line tool (like TV remote for Kubernetes)
- `delete` = remove something
- `-f <url>` = from this file/configuration
- `--ignore-not-found=true` = don't error if already deleted

**Analogy:** Like uninstalling an app from your phone

```bash
kubectl delete namespace kserve --ignore-not-found=true
```
**What it means:** Delete the "kserve" folder in Kubernetes
**Why:** Namespaces are like folders - deleting the folder deletes everything inside
**Analogy:** Deleting a folder deletes all files in it

```bash
sleep 30
```
**What it means:** Wait 30 seconds
**Why:** Give AWS time to delete resources
**Analogy:** Like waiting for water to drain before opening the washing machine

---

## Script 1: setup-eks-cluster.sh

### What It Does (In Simple Terms)

Creates your "restaurant building" in AWS cloud. This is the foundation for everything.

### What Gets Created

1. **EKS Cluster** - The main computer cluster
2. **VPC** - Private network (like a private road to your restaurant)
3. **3 Servers (EC2 instances)** - The actual computers
4. **Security rules** - Who can access what

### Line-by-Line Explanation

```bash
command -v aws >/dev/null 2>&1 || { echo "aws CLI is not installed"; exit 1; }
```
**What it means:** Check if AWS CLI is installed, if not, show error and stop
**Breaking it down:**
- `command -v aws` = check if "aws" command exists
- `>/dev/null` = throw away the output (don't show it)
- `2>&1` = include error messages too
- `||` = OR (if previous fails, do this)
- `{ ... }` = group of commands to run
- `exit 1` = stop the script with error code 1

**Analogy:** Like checking if you have a key before trying to unlock a door

```bash
aws sts get-caller-identity >/dev/null 2>&1 || { echo "AWS credentials not configured"; exit 1; }
```
**What it means:** Test if AWS credentials work
**What it does:**
- `aws sts get-caller-identity` = ask AWS "who am I?"
- If it fails = credentials don't work

**Analogy:** Like checking if your key actually works in the lock

```bash
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
```
**What it means:** Variables (like labeled boxes to store information)
- `CLUSTER_NAME` = what to call our cluster
- `REGION` = where in AWS to build it (Virginia data center)

**Analogy:** Like deciding to name your restaurant "Joe's Diner" and build it in "New York"

```bash
if eksctl get cluster --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
```
**What it means:** Check if a cluster with this name already exists
**Breaking it down:**
- `if` = start a conditional check
- `eksctl get cluster` = ask eksctl to find a cluster
- `--name $CLUSTER_NAME` = with this name (uses our variable)
- `--region $REGION` = in this region
- `>/dev/null 2>&1` = don't show output
- `; then` = if true, do the next part

**Analogy:** Like checking if there's already a restaurant with your name

```bash
read -p "Do you want to delete and recreate it? (yes/no): " -r
```
**What it means:** Ask the user a question and wait for answer
- `read` = wait for user input
- `-p "text"` = show this prompt text
- `-r` = read input as-is (no special processing)

**Analogy:** Like asking "Are you sure?" before deleting something

```bash
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
```
**What it means:** Check if user typed "yes" (any capitalization)
**Breaking it down:**
- `[[ ... ]]` = test condition
- `$REPLY` = the user's answer
- `=~` = matches (regex comparison)
- `^[Yy][Ee][Ss]$` = pattern for "yes", "Yes", "YES", etc.
  - `^` = start of text
  - `[Yy]` = Y or y
  - `[Ee]` = E or e
  - `[Ss]` = S or s
  - `$` = end of text

**Analogy:** Like checking if someone said "okay" in any form: "ok", "OK", "Okay"

```bash
eksctl create cluster -f $CONFIG_FILE
```
**What it means:** Create the EKS cluster using a configuration file
**What happens:**
- Reads `eks-cluster-config.yaml`
- Creates VPC, subnets, internet gateway
- Launches 3 EC2 servers
- Sets up networking
- Configures security

**Time:** 15-20 minutes (AWS needs to set up all infrastructure)

**Analogy:** Like building a restaurant from blueprints - takes time!

```bash
eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$REGION
```
**What it means:** Save connection info to your computer
**What it does:**
- Creates/updates `~/.kube/config` file
- This file tells kubectl how to connect to your cluster

**Analogy:** Like saving a phone number in your contacts so you can call later

```bash
kubectl cluster-info
```
**What it means:** Show information about the cluster
**What you see:**
- Control plane URL
- Status of services

**Analogy:** Like checking your restaurant's address and hours

```bash
eksctl utils associate-iam-oidc-provider --cluster=$CLUSTER_NAME --region=$REGION --approve
```
**What it means:** Enable "IRSA" (IAM Roles for Service Accounts)
**Why we need it:** Allows pods in Kubernetes to access AWS services securely
**How it works:**
- OIDC = identity provider (like Google login)
- Lets Kubernetes pods prove their identity to AWS
- AWS gives them permissions based on that identity

**Analogy:** Like giving your employees ID badges so they can access different rooms

---

## Script 2: setup-alb-controller.sh

### What It Does (In Simple Terms)

Installs the "front door" system (Load Balancer) that lets people access your services from the internet.

### What It Creates

1. **IAM Policy** - Permission rules for load balancer
2. **Service Account** - Identity for the load balancer controller
3. **cert-manager** - Manages SSL certificates (like HTTPS padlocks)
4. **ALB Controller** - The actual load balancer software

### Line-by-Line Explanation

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```
**What it means:** Get your AWS account number
**Breaking it down:**
- `$( ... )` = run command and save result
- `aws sts get-caller-identity` = ask AWS who you are
- `--query Account` = just get the account ID part
- `--output text` = give me plain text (not JSON)

**Analogy:** Like looking up your bank account number

```bash
curl -o iam-policy.json https://raw.githubusercontent.com/...
```
**What it means:** Download a file from the internet
- `curl` = download tool (like a web browser for scripts)
- `-o iam-policy.json` = save it with this name
- `https://...` = from this URL

**Analogy:** Like downloading a PDF from a website

```bash
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
```
**What it means:** Build the full "address" of the IAM policy
**What is ARN:** Amazon Resource Name - like a full mailing address
- `arn:aws:iam` = AWS IAM service
- `::${AWS_ACCOUNT_ID}` = in your account
- `:policy/AWSLoad...` = specifically this policy

**Analogy:** Like writing a full address: "123 Main St, New York, NY 10001"

```bash
if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo "Policy already exists"
else
    aws iam create-policy ...
fi
```
**What it means:** Check if policy exists, if not, create it
**Why:** Avoid errors from trying to create something twice

**Analogy:** Like checking if a contact exists before adding it to your phone

```bash
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --approve
```
**What it means:** Create a special account for the load balancer with permissions
**Breaking it down:**
- `eksctl create iamserviceaccount` = create account
- `--cluster=...` = in this cluster
- `--namespace=kube-system` = in the system namespace
- `--name=...` = call it this
- `--attach-policy-arn=...` = give it these permissions
- `--override-existing...` = replace if exists
- `--approve` = don't ask for confirmation

**What it does behind the scenes:**
1. Creates IAM role in AWS
2. Creates service account in Kubernetes
3. Links them together (IRSA magic!)

**Analogy:** Like creating an employee account and giving them an access badge

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```
**What it means:** Install cert-manager into Kubernetes
**Breaking it down:**
- `kubectl apply` = install/create resources
- `--validate=false` = don't validate (sometimes needed for compatibility)
- `-f <url>` = from this file

**What cert-manager does:**
- Manages SSL/TLS certificates
- Automatically renews them
- Needed by KServe for secure communication

**Analogy:** Like installing a security system that manages door locks

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```
**What it means:** Wait until cert-manager is fully running (max 5 minutes)
**Breaking it down:**
- `kubectl wait` = wait for something
- `--for=condition=ready` = wait until ready
- `pod` = waiting for pods
- `-l app.kubernetes.io/instance=cert-manager` = with this label (find cert-manager pods)
- `-n cert-manager` = in cert-manager namespace
- `--timeout=300s` = give up after 300 seconds

**Why:** Next steps need cert-manager to be working

**Analogy:** Like waiting for your oven to preheat before baking

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```
**What it means:** Add AWS's Helm charts repository and update it
**What is Helm:** Package manager for Kubernetes (like apt/yum for Linux, or App Store)
**What are charts:** Pre-packaged applications

**Analogy:** Like adding a new app store to your phone

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=$REGION \
    --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
```
**What it means:** Install/upgrade the ALB controller using Helm
**Breaking it down:**
- `helm upgrade --install` = install or upgrade if exists
- `aws-load-balancer-controller` = name it this
- `eks/aws-load-balancer-controller` = use this chart
- `-n kube-system` = in kube-system namespace
- `--set ...` = configuration options:
  - `clusterName` = which cluster
  - `serviceAccount.create=false` = don't create (we already did)
  - `serviceAccount.name` = use this existing one
  - `region` = AWS region
  - `vpcId=$( ... )` = get VPC ID with a command:
    - `aws eks describe-cluster` = get cluster info
    - `--query "...vpcId"` = extract just the VPC ID

**What it installs:**
- ALB controller deployment
- Webhooks for automation
- CRDs (Custom Resource Definitions)

**Analogy:** Like installing and configuring a smart doorbell system

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=300s
```
**What it means:** Wait for ALB controller to be ready

```bash
rm -f iam-policy.json
```
**What it means:** Delete the temporary policy file we downloaded
- `rm` = remove
- `-f` = force (don't ask for confirmation)

**Analogy:** Like throwing away the instruction manual after assembly

---

## Script 3: install-kserve.sh

### What It Does (In Simple Terms)

Installs KServe - the "chef" that actually serves your ML models to users.

### Components Installed

1. **Knative Serving** - Serverless platform (auto-scales)
2. **Kourier** - Network routing (lightweight alternative to Istio)
3. **KServe** - Model serving framework
4. **ClusterServingRuntimes** - Pre-built model servers (sklearn, pytorch, etc.)

### Line-by-Line Explanation

```bash
if kubectl get namespace cert-manager &>/dev/null; then
    echo "✓ cert-manager already installed"
else
    echo "✗ cert-manager not found. Please run script 2 first."
    exit 1
fi
```
**What it means:** Check if cert-manager exists, if not, stop
**Breaking it down:**
- `kubectl get namespace cert-manager` = try to get cert-manager namespace
- `&>/dev/null` = hide all output (both stdout and stderr)
  - `&>` = redirect both output and errors
  - `/dev/null` = the "trash can" (discard it)
- `then ... else ... fi` = if-else block

**Why:** cert-manager must exist before KServe can work

**Analogy:** Like checking you have flour before starting to bake bread

```bash
KNATIVE_VERSION="v1.15.0"
```
**What it means:** Variable for which version of Knative to install

```bash
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml
```
**What it means:** Install Knative CRDs (Custom Resource Definitions)
**What are CRDs:**
- Like new "types" of objects in Kubernetes
- CRD = template/blueprint for custom resources
- For example: "Service", "Revision", "Route"

**Analogy:** Like installing new Lego piece types so you can build more things

```bash
kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml
```
**What it means:** Install Knative core components
**What gets installed:**
- Activator (manages incoming requests)
- Autoscaler (scales pods up/down)
- Controller (manages Knative resources)
- Webhook (validates configurations)

**Analogy:** Like installing the engine, transmission, and wheels of a car

```bash
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml
```
**What it means:** Install Kourier (networking layer)
**What is Kourier:**
- Lightweight networking for Knative
- Routes traffic to the right pods
- Simpler than Istio (alternative)

**Analogy:** Like installing the road system that leads to your restaurant

```bash
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```
**What it means:** Tell Knative to use Kourier for networking
**Breaking it down:**
- `kubectl patch` = modify existing resource
- `configmap/config-network` = this specific config
- `--namespace knative-serving` = in this namespace
- `--type merge` = merge with existing data (don't replace)
- `--patch '{ JSON }'` = apply this change:
  - Set `ingress-class` to Kourier

**Why:** Knative needs to know which networking system to use

**Analogy:** Like telling your GPS to use "highways only" mode

```bash
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"example.com":""}}'
```
**What it means:** Configure default domain
**What it does:**
- Removes "example.com" as domain suffix
- Services will get auto-generated URLs

**Result:** URLs like `http://my-service.namespace.svc.cluster.local`

```bash
kubectl wait --for=condition=ready pod --all -n knative-serving --timeout=600s
```
**What it means:** Wait for ALL Knative pods to be ready (max 10 minutes)
- `--all` = all pods (not just specific ones)
- `timeout=600s` = 10 minutes max

**Why:** Can't proceed until Knative is fully operational

```bash
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml
```
**What it means:** Install KServe main components
**What gets installed:**
- KServe controller (manages InferenceServices)
- Webhooks (validate configurations)
- CRDs (InferenceService, ServingRuntime, etc.)

**Analogy:** Like hiring the head chef who manages all the cooking

```bash
for i in {1..30}; do
    ENDPOINTS=$(kubectl get endpoints kserve-webhook-server-service -n kserve -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -n "$ENDPOINTS" ]; then
        echo "✓ Webhook endpoints are ready"
        break
    fi
    echo "Waiting for webhook endpoints... ($i/30)"
    sleep 10
done
```
**What it means:** Wait until webhook has an IP address (try 30 times)
**Breaking it down:**
- `for i in {1..30}; do ... done` = loop 30 times
- `ENDPOINTS=$( ... )` = try to get webhook IP
- `kubectl get endpoints` = get endpoint (IP addresses)
- `-o jsonpath='{...}'` = extract specific field with JSONPath
  - `.subsets[*]` = all subsets
  - `.addresses[*]` = all addresses
  - `.ip` = the IP field
- `|| echo ""` = if command fails, use empty string
- `if [ -n "$ENDPOINTS" ]` = if ENDPOINTS is not empty
- `break` = exit the loop
- `sleep 10` = wait 10 seconds before next try

**Why:** Webhook MUST be ready before we can create ClusterServingRuntimes

**Analogy:** Like waiting for the phone line to connect before talking

```bash
sleep 20
```
**What it means:** Extra safety buffer (20 seconds)
**Why:** Even if webhook has IP, it might not be fully ready to receive requests

**Analogy:** Like waiting an extra minute after the oven beeps

```bash
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-cluster-resources.yaml
```
**What it means:** Install ClusterServingRuntimes
**What are these:**
- Pre-configured model servers for common frameworks
- sklearn (scikit-learn)
- xgboost
- pytorch
- tensorflow
- lightgbm
- paddle
- pmml
- triton

**Why:** So you don't have to configure model servers from scratch

**Analogy:** Like having pre-programmed recipes in a cooking app

```bash
kubectl create namespace mlflow-kserve-test --dry-run=client -o yaml | kubectl apply -f -
```
**What it means:** Create namespace (or do nothing if exists)
**Breaking it down:**
- `kubectl create namespace mlflow-kserve-test` = create namespace
- `--dry-run=client` = don't actually create, just generate YAML
- `-o yaml` = output as YAML
- `|` = pipe (send output to next command)
- `kubectl apply -f -` = apply YAML from stdin (the pipe)

**Why use this complex command:**
- `apply` is idempotent (safe to run multiple times)
- `create` would error if namespace exists

**Analogy:** Like creating a folder, but if it exists, just use it

### 🎉 NEW AUTOMATION: Internet-Facing Kourier LoadBalancer

**Added in January 2026 - This is automatic now!**

After installing Knative and Kourier, the script now automatically configures the LoadBalancer to be internet-facing:

```bash
echo -e "\n${YELLOW}Configuring Kourier LoadBalancer for external access...${NC}"

# Check if Kourier service exists
if kubectl get svc kourier -n kourier-system &>/dev/null; then
    echo "Kourier service found, making it internet-facing..."

    # Delete the default internal LoadBalancer
    kubectl delete svc kourier -n kourier-system

    # Apply internet-facing configuration
    kubectl apply -f ../manifests/kourier-service.yaml

    # Wait for new LoadBalancer to be provisioned
    echo "Waiting for LoadBalancer to be provisioned..."
    for i in {1..30}; do
        EXTERNAL_IP=$(kubectl get svc kourier -n kourier-system \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
            kubectl get svc kourier -n kourier-system \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

        if [ -n "$EXTERNAL_IP" ]; then
            echo -e "${GREEN}✓ LoadBalancer provisioned: $EXTERNAL_IP${NC}"
            break
        fi
        echo "  Attempt $i/30..."
        sleep 10
    done
fi
```

**What it does:**
1. Checks if Kourier service exists in `kourier-system` namespace
2. Deletes the default internal LoadBalancer that Knative creates
3. Applies a new service configuration with internet-facing annotations
4. Waits up to 5 minutes for AWS to provision the public LoadBalancer
5. Displays the external endpoint when ready

**What the new service configuration includes:**
```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

**Why this is important:**
- **Before:** LoadBalancer was created as "internal" - only accessible from VPC
- **After:** LoadBalancer is "internet-facing" - accessible from anywhere
- **Result:** Your InferenceServices are immediately accessible without manual fixes

**Analogy:** Like automatically opening the front door to your restaurant instead of keeping it locked

---

## Script 4: setup-s3-mlflow.sh

### What It Does (In Simple Terms)

Creates an S3 "pantry" where MLflow stores model artifacts, and gives KServe permission to access it.

### What It Creates

1. **S3 Bucket** - Storage for models and artifacts
2. **IAM Policy** - Permission rules for S3 access
3. **Service Account** - Identity for KServe pods
4. **IAM Role** - Linked to service account via IRSA

### Line-by-Line Explanation

```bash
BUCKET_NAME="kserve-mlflow-artifacts-$(aws sts get-caller-identity --query Account --output text)"
```
**What it means:** Create bucket name using account ID
**Result:** Something like `kserve-mlflow-artifacts-123456789012`
**Why include account ID:**
- S3 bucket names must be globally unique
- Account ID ensures uniqueness

**Analogy:** Like naming your storage unit "Storage-YourPhoneNumber"

```bash
if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION
else
    echo "Bucket already exists"
fi
```
**What it means:** Check if bucket exists, create if it doesn't
**Breaking it down:**
- `aws s3 ls "s3://$BUCKET_NAME"` = list bucket contents
- `2>&1` = redirect errors to stdout (so we can grep them)
- `| grep -q 'NoSuchBucket'` = check if error contains "NoSuchBucket"
  - `|` = pipe output to grep
  - `grep -q` = quiet mode (just return true/false)
- `aws s3api create-bucket` = create the bucket
  - Uses `s3api` (low-level) instead of `s3` (high-level)

**Note about regions:**
- us-east-1 doesn't need `--create-bucket-configuration`
- Other regions do

```bash
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled
```
**What it means:** Enable versioning on the bucket
**What is versioning:**
- Keeps old versions of files when you overwrite them
- Can recover accidentally deleted/modified files
- Each version gets a unique ID

**Why:** Safety - can recover previous model versions

**Analogy:** Like Google Docs keeping version history

```bash
cat > s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
```
**What it means:** Create a JSON file with IAM policy
**Breaking it down:**
- `cat > s3-policy.json <<EOF ... EOF` = create file with this content
  - `cat >` = output to file
  - `<<EOF ... EOF` = here-document (multi-line string)
- Policy structure:
  - `Version` = policy language version (always 2012-10-17)
  - `Statement` = list of permissions
  - `Effect: Allow` = grant permission (vs Deny)
  - `Action` = what actions are allowed:
    - `s3:GetObject` = download files
    - `s3:PutObject` = upload files
    - `s3:DeleteObject` = delete files
    - `s3:ListBucket` = list what's in bucket
  - `Resource` = what this applies to:
    - Bucket itself
    - All objects in bucket (`/*`)

**Analogy:** Like writing permissions: "John can read, write, and delete files in this folder"

```bash
POLICY_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/KServeS3AccessPolicy"

if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    POLICY_VERSION=$(aws iam create-policy-version \
        --policy-arn $POLICY_ARN \
        --policy-document file://s3-policy.json \
        --set-as-default \
        --query 'PolicyVersion.VersionId' \
        --output text)
    echo "✓ Policy updated (version: $POLICY_VERSION)"
else
    aws iam create-policy \
        --policy-name KServeS3AccessPolicy \
        --policy-document file://s3-policy.json
    echo "✓ IAM policy created"
fi
```
**What it means:** Create or update the IAM policy
**Breaking it down:**
- Check if policy exists
- If yes: Create new version (IAM policies can have multiple versions)
  - `create-policy-version` = new version
  - `--set-as-default` = make this the active version
  - Old versions remain for rollback
- If no: Create new policy

**Why versions:** Can rollback if new version causes issues

**Analogy:** Like saving document versions - can go back to previous

```bash
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=mlflow-kserve-test \
    --name=kserve-sa \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --approve
```
**What it means:** Create service account with S3 permissions using IRSA
**What happens:**
1. eksctl creates IAM role in AWS
2. IAM role has trust policy for OIDC provider
3. IAM role has S3 policy attached
4. Service account in Kubernetes gets annotated with role ARN
5. Pods using this service account automatically get AWS credentials

**The magic:** Pods don't need hardcoded credentials!

**How IRSA works:**
```
Pod starts → Sees service account → Kubernetes injects OIDC token
→ Pod uses token to call AWS STS → STS returns temporary credentials
→ Pod uses credentials to access S3
```

**Analogy:** Like having a work ID badge that automatically gives you building access

```bash
rm -f s3-policy.json
```
**What it means:** Delete temporary policy file

---

## Script 5: cleanup.sh (Now renamed to 6-cleanup.sh)

### What It Does (In Simple Terms)

**Complete teardown** of everything we built. Like demolishing the restaurant and returning the land.

### 🎉 NEW AUTOMATION (January 2026)

The cleanup script has been enhanced to handle:
1. **gp3 StorageClass deletion** - Removes the auto-created gp3 StorageClass
2. **LoadBalancer verification** - Better detection of orphaned LoadBalancers
3. **Improved error handling** - More robust cleanup with better messages

### Why So Complex (11KB)

Because AWS resources are interconnected:
- Can't delete VPC until subnets deleted
- Can't delete subnets until ENIs deleted
- Can't delete security groups until load balancers deleted
- Can't delete StorageClass until PVCs deleted
- etc.

### Phase-by-Phase Explanation

#### Phase 1: Kubernetes Resources

```bash
kubectl delete inferenceservice --all -n mlflow-kserve-test --ignore-not-found=true --timeout=60s || true
```
**What it means:** Delete all InferenceServices (with timeout)
**Breaking it down:**
- `--all` = all resources of this type
- `--timeout=60s` = give up after 60 seconds
- `|| true` = even if this fails, continue
  - `||` = OR
  - `true` = always succeeds

**Why timeout:** Sometimes resources get stuck in "Terminating" state

```bash
kubectl delete svc --all -n knative-serving --field-selector spec.type=LoadBalancer --ignore-not-found=true --timeout=60s || true
```
**What it means:** Delete LoadBalancer services
**Why critical:** LoadBalancer services create AWS ALBs/NLBs
- If not deleted properly, they become "orphaned"
- Orphaned load balancers cost money (~$16-22/month each)
- Can prevent VPC deletion

**Breaking it down:**
- `svc` = services
- `--field-selector spec.type=LoadBalancer` = only LoadBalancer type
  - `field-selector` = filter by field value
  - `spec.type=LoadBalancer` = where type equals LoadBalancer

```bash
sleep 60
```
**What it means:** Wait 60 seconds
**Why:** Give AWS time to delete load balancers
- Load balancer deletion is async (happens in background)
- Must complete before VPC can be deleted

**Analogy:** Like waiting for checkout at a store - can't leave until transaction completes

#### Phase 2: IAM Service Accounts

```bash
eksctl delete iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=mlflow-kserve-test \
    --name=kserve-sa \
    2>/dev/null || echo "  kserve-sa not found or already deleted"
```
**What it means:** Delete service account and its IAM role
**What gets deleted:**
- Kubernetes service account
- IAM role in AWS
- Trust relationship between them

**Breaking it down:**
- `2>/dev/null` = hide error messages
- `|| echo "..."` = if command fails, print this message

**Why delete:** IAM roles can't be deleted if they're attached to service accounts

#### Phase 2.5: StorageClass Cleanup (NEW)

**Added in January 2026:**

```bash
echo -e "\n${YELLOW}Deleting gp3 StorageClass...${NC}"
kubectl delete storageclass gp3 --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ gp3 StorageClass deleted (if it existed)${NC}"
```

**What it means:** Delete the gp3 StorageClass we auto-created
**Breaking it down:**
- `kubectl delete storageclass gp3` = remove the gp3 StorageClass
- `--ignore-not-found=true` = don't error if it doesn't exist
- `2>/dev/null` = hide error messages
- `|| true` = continue even if this fails

**Why delete it:**
- We auto-created it in Script 6 (deploy-mlflow-on-eks.sh)
- Should clean up all resources we created
- Won't affect cluster if it doesn't exist

**What happens to PVCs using gp3:**
- Must be deleted BEFORE deleting StorageClass
- Already handled in Phase 1 (namespace deletion removes PVCs)

**Analogy:** Like removing custom shelves you installed before moving out

#### Phase 3: EKS Cluster

```bash
eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait
```
**What it means:** Delete entire cluster and wait for completion
**What gets deleted:**
- All nodes (EC2 instances)
- VPC and networking
- Security groups
- IAM roles for nodes
- CloudFormation stacks

**How long:** 10-15 minutes

**Breaking it down:**
- `--wait` = don't return until deletion complete
  - Without this, command returns immediately but deletion continues

**Analogy:** Like demolishing a building - takes time and must be done carefully

#### Phase 4: IAM Policies

```bash
VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
for version in $VERSIONS; do
    aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version 2>/dev/null || true
done
aws iam delete-policy --policy-arn $POLICY_ARN
```
**What it means:** Delete policy and all its versions
**Breaking it down:**
- `list-policy-versions` = get all versions
- `--query 'Versions[?!IsDefaultVersion].VersionId'` =
  - Get Versions array
  - Filter: `?!IsDefaultVersion` = where NOT default version
  - Extract: `.VersionId` = just the version ID
- Loop through each version and delete it
- Finally, delete the policy itself

**Why:** Must delete all non-default versions before deleting policy

**Analogy:** Like deleting all drafts before deleting the document

#### Phase 5: S3 Bucket

```bash
# Delete all versions
aws s3api delete-objects --bucket $BUCKET_NAME \
    --delete "$(aws s3api list-object-versions --bucket $BUCKET_NAME \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)"

# Delete delete markers
aws s3api delete-objects --bucket $BUCKET_NAME \
    --delete "$(aws s3api list-object-versions --bucket $BUCKET_NAME \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)"

# Delete remaining objects
aws s3 rm s3://$BUCKET_NAME --recursive

# Delete bucket
aws s3 rb s3://$BUCKET_NAME
```
**What it means:** Empty and delete bucket (handling versioning)
**Why so complex:** Versioned buckets have:
- Current versions
- Old versions
- Delete markers (tombstones for deleted files)

**Breaking it down:**
- `list-object-versions` = list all versions
- `--query '{Objects: ...}'` = format for delete-objects API
- `delete-objects` = batch delete (faster than one-by-one)
- `s3 rm --recursive` = delete any remaining files
- `s3 rb` = remove bucket (rb = remove bucket)

**Must be empty:** Can't delete bucket unless completely empty

**Analogy:** Like emptying a storage unit before canceling it

#### Phase 6: Orphaned Resources

```bash
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?contains(LoadBalancerName, 'kserve')].LoadBalancerArn" --output text)
```
**What it means:** Find load balancers with "kserve" in name
**Breaking it down:**
- `describe-load-balancers` = list all ALBs/NLBs
- `--query "LoadBalancers[?contains(...)]"` = filter:
  - `LoadBalancers` = array of load balancers
  - `[?contains(LoadBalancerName, 'kserve')]` = where name contains "kserve"
  - `.LoadBalancerArn` = get just the ARN

**Why:** Sometimes load balancers don't get deleted properly

**What to do:** The script tells you the command to manually delete

**Similar checks for:**
- Security groups
- EBS volumes
- CloudWatch logs

---

## Script 6: deploy-mlflow-on-eks.sh

### What It Does (In Simple Terms)

Deploys MLflow server inside your Kubernetes cluster (alternative to using EC2).

### What It Creates

1. **PersistentVolume** - Disk storage for MLflow database
2. **Deployment** - MLflow server pod
3. **LoadBalancer Service** - External access
4. **ClusterIP Service** - Internal access

### Line-by-Line Explanation

```bash
BUCKET_NAME="kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}"

if ! aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
    echo "✗ S3 bucket not found. Please run script 4 first."
    exit 1
fi
```
**What it means:** Check prerequisites (S3 bucket exists)
**Why:** MLflow needs S3 to store artifacts

### 🎉 NEW AUTOMATION #1: Auto-Create gp3 StorageClass

**Added in January 2026 - This is automatic now!**

Before deploying MLflow, the script checks if the gp3 StorageClass exists and creates it if missing:

```bash
echo -e "\n${YELLOW}Checking for gp3 StorageClass...${NC}"

if ! kubectl get storageclass gp3 &>/dev/null; then
    echo -e "${YELLOW}gp3 StorageClass not found. Creating it...${NC}"

    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  iops: "3000"
  throughput: "125"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

    echo -e "${GREEN}✓ gp3 StorageClass created${NC}"
else
    echo -e "${GREEN}✓ gp3 StorageClass already exists${NC}"
fi
```

**What it does:**
1. Checks if gp3 StorageClass exists
2. If not found, creates it with optimized settings
3. Uses EBS CSI driver (already installed in EKS)

**Why this is important:**
- **Before:** EKS only has gp2 by default - MLflow PVC would fail
- **After:** gp3 is auto-created - MLflow deploys successfully
- **Benefits:**
  - gp3 is more cost-effective than gp2
  - Better performance: 3000 IOPS, 125 MB/s throughput
  - Volume expansion supported

**Analogy:** Like automatically installing the right shelf brackets before hanging a shelf

### 🎉 NEW AUTOMATION #2: Auto-Install boto3 in MLflow

**Added in January 2026 - This is automatic now!**

The MLflow deployment manifest now includes automatic boto3 installation:

```yaml
containers:
  - name: mlflow
    image: ghcr.io/mlflow/mlflow:v2.10.2
    command: ["/bin/sh", "-c"]
    args:
      - |
        pip install --upgrade boto3 awscli mlflow && \
        mlflow server \
          --host=0.0.0.0 \
          --port=5000 \
          --default-artifact-root=s3://REPLACE_WITH_YOUR_BUCKET_NAME/artifacts \
          --backend-store-uri=/mlflow/mlflow.db \
          --serve-artifacts \
          --allowed-hosts "*"
```

**What it does:**
1. When container starts, runs pip install first
2. Installs boto3, awscli, and latest mlflow
3. Then starts MLflow server
4. Takes 30-40 seconds extra on first startup

**Why this is important:**
- **Before:** Official MLflow image doesn't include boto3 → S3 artifact storage fails
- **After:** boto3 installed automatically → S3 works out of the box
- **Result:** No custom Docker images needed

**The error this fixes:**
```
ModuleNotFoundError: No module named 'boto3'
```

**Analogy:** Like automatically installing batteries in a device before turning it on

### 🎉 NEW AUTOMATION #3: Internet-Facing MLflow LoadBalancer

**Added in January 2026 - This is automatic now!**

The MLflow service is now configured as internet-facing by default:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mlflow-server
  namespace: mlflow-kserve-test
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: mlflow-server
  ports:
    - name: http
      port: 5000
      targetPort: 5000
```

**What the annotations do:**
- `aws-load-balancer-scheme: "internet-facing"` → Public LoadBalancer
- `aws-load-balancer-type: "nlb"` → Use Network Load Balancer (faster, cheaper than ALB)

**Why this is important:**
- **Before:** LoadBalancer created as "internal" → Not accessible from browser
- **After:** LoadBalancer is "internet-facing" → Accessible from anywhere
- **Result:** MLflow UI works immediately

**Analogy:** Like making sure your store has a front door that opens to the street, not just to the back alley

```bash
sed "s/REPLACE_WITH_YOUR_BUCKET_NAME/$BUCKET_NAME/g" ../manifests/mlflow-server.yaml > /tmp/mlflow-server-configured.yaml
```
**What it means:** Replace placeholder in YAML with actual bucket name
**Breaking it down:**
- `sed` = stream editor (find and replace in files)
- `"s/OLD/NEW/g"` = substitute OLD with NEW globally
  - `s` = substitute
  - `/` = delimiter
  - `g` = global (all occurrences)
- `../manifests/mlflow-server.yaml` = input file
- `> /tmp/...` = output to temporary file

**Why:** The manifest has placeholder that needs actual bucket name

**Analogy:** Like filling in blanks on a form

```bash
kubectl apply -f /tmp/mlflow-server-configured.yaml
```
**What it means:** Deploy MLflow using the configured YAML
**What gets created:**
- PersistentVolumeClaim (20GB disk)
- Deployment (MLflow server pod)
- LoadBalancer Service (external access)
- ClusterIP Service (internal access)

```bash
kubectl wait --for=condition=available deployment/mlflow-server -n $NAMESPACE --timeout=300s
```
**What it means:** Wait for deployment to be ready (max 5 minutes)
**Breaking it down:**
- `--for=condition=available` = wait for "available" condition
  - Available = minimum replicas are running
- `deployment/mlflow-server` = this specific deployment

**What happens during this time:**
1. Kubernetes schedules pod to a node
2. Node pulls MLflow Docker image (takes time if not cached)
3. Pod starts up
4. Readiness probe checks if MLflow is responding
5. Once ready, deployment marked as "available"

```bash
for i in {1..30}; do
    MLFLOW_URL=$(kubectl get svc mlflow-server -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                 kubectl get svc mlflow-server -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$MLFLOW_URL" ]; then
        break
    fi
    echo "Waiting for load balancer... ($i/30)"
    sleep 10
done
```
**What it means:** Poll for load balancer URL (try 30 times)
**Why two JSONPath queries:**
- First tries `hostname` (ALB gives hostname)
- Second tries `ip` (NLB gives IP)
- One of them will work depending on LB type

**Breaking it down:**
- `for i in {1..30}` = loop 30 times
- Try to get hostname OR IP
- `|| echo ""` = if both fail, empty string
- `if [ -n "$MLFLOW_URL" ]` = if URL is not empty
- `break` = exit loop
- `sleep 10` = wait 10 seconds between attempts

**How long:** Up to 5 minutes (30 attempts × 10 seconds)

**Why so long:** AWS needs to:
1. Create load balancer
2. Register targets (pods)
3. Health check targets
4. Assign DNS name

```bash
rm -f /tmp/mlflow-server-configured.yaml
```
**What it means:** Delete temporary file

**Output shows:**
- MLflow URL (for browser/API)
- Environment variables to set
- How to test connection
- Useful commands

---

## Helper: get-inference-url.sh

### What It Does (In Simple Terms)

Gets the external URL where you can access your deployed model.

### 🎉 IMPORTANT FIXES (January 2026)

This script was updated to fix two critical issues:
1. **Using predictor URL** (not main InferenceService URL)
2. **Checking kourier-system namespace** (where Kourier actually is)

### Line-by-Line Explanation

#### Getting the Predictor URL (FIXED)

```bash
# Get the predictor URL (this is the actual endpoint)
PREDICTOR_URL=$(kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE \
    -o jsonpath='{.status.components.predictor.url}' 2>/dev/null || echo "")

# Fallback to Knative Service if predictor URL not available
if [ -z "$PREDICTOR_URL" ]; then
    PREDICTOR_URL=$(kubectl get ksvc ${ISVC_NAME}-predictor -n $NAMESPACE \
        -o jsonpath='{.status.url}' 2>/dev/null || echo "")
fi
```

**What it means:** Get the correct URL with `-predictor` suffix
**Why this matters:**
- **Wrong (old way):** `http://mlflow-wine-classifier.namespace.example.com` → 404 errors
- **Correct (new way):** `http://mlflow-wine-classifier-predictor.namespace.example.com` → Works!

**Breaking it down:**
- `.status.components.predictor.url` = get predictor component's URL
- `2>/dev/null` = hide errors
- `|| echo ""` = if fails, use empty string
- Fallback tries to get Knative Service directly

**Why two approaches:**
- Primary: Use InferenceService status (cleaner)
- Fallback: Query Knative Service directly (more reliable)

**Analogy:** Like getting the actual delivery entrance, not just the building address

#### Finding Kourier LoadBalancer (FIXED)

```bash
# Try Kourier in kourier-system (EKS setup)
INGRESS_HOST=$(kubectl get svc -n kourier-system kourier \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    kubectl get svc -n kourier-system kourier \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

# Fallback to knative-serving namespace
if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl get svc -n knative-serving kourier \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
        kubectl get svc -n knative-serving kourier \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi
```

**What it means:** Look for Kourier in the correct namespace
**Why this matters:**
- **Wrong (old way):** Only checked `knative-serving` → Failed to find Kourier
- **Correct (new way):** Checks `kourier-system` first → Finds Kourier

**Breaking it down:**
- First checks `kourier-system` (where our setup puts it)
- Tries both hostname (NLB) and IP
- Falls back to `knative-serving` for other setups

**Why the fallback:**
- Our EKS setup: Kourier is in `kourier-system`
- Some other setups: Kourier might be in `knative-serving`
- Covers both cases

**Analogy:** Like checking the main parking lot first, then the overflow lot

#### Verifying LoadBalancer is Public (NEW)

```bash
if command -v aws &> /dev/null; then
    echo -e "\n4. Verifying LoadBalancer configuration..."
    LB_SCHEME=$(aws elbv2 describe-load-balancers --region us-east-1 2>/dev/null \
        --query "LoadBalancers[?contains(DNSName, '$(echo $INGRESS_HOST | cut -d'-' -f1-3)')].Scheme" \
        --output text 2>/dev/null || echo "")

    if [ "$LB_SCHEME" = "internet-facing" ]; then
        echo "✓ LoadBalancer is internet-facing (publicly accessible)"
    elif [ "$LB_SCHEME" = "internal" ]; then
        echo "⚠️  WARNING: LoadBalancer is INTERNAL (not publicly accessible)"
        echo "   To fix: kubectl delete svc kourier -n kourier-system"
        echo "           kubectl apply -f manifests/kourier-service.yaml"
    fi
fi
```

**What it means:** Check if LoadBalancer is public or private
**Breaking it down:**
- `command -v aws` = check if aws CLI exists
- `describe-load-balancers` = get all load balancers
- `--query "LoadBalancers[?contains(...)]"` = filter by DNS name
- Extract just the `Scheme` field (internet-facing or internal)
- Show warning if internal

**Why this is helpful:**
- Prevents confusion when endpoints don't work
- Provides exact fix commands
- Only runs if aws CLI is available

**Analogy:** Like checking if your store sign faces the street or the alley

```bash
kubectl get inferenceservice $ISVC_NAME -n $NAMESPACE -o jsonpath='{.status.url}'
```
**What it means:** Get the URL from InferenceService status (OLD - kept for reference)
**What is .status.url:**
- KServe sets this when service is ready
- Format: `http://service-name.namespace.example.com`
- ⚠️ **This is NOT the actual endpoint** - need predictor URL instead!

```bash
SERVICE_HOSTNAME=$(echo $ISVC_URL | sed 's|http://||' | sed 's|https://||' | cut -d'/' -f1)
```
**What it means:** Extract just the hostname from URL
**Breaking it down:**
- `echo $ISVC_URL` = print the URL
- `| sed 's|http://||'` = remove "http://"
  - `s|OLD|NEW|` = substitute (using | instead of /)
- `| sed 's|https://||'` = remove "https://"
- `| cut -d'/' -f1` = cut on "/" and take first field
  - `cut -d'/'` = split on /
  - `-f1` = field 1 (the hostname)

**Example:**
```
Input:  http://my-service.namespace.example.com/path
Output: my-service.namespace.example.com
```

```bash
INGRESS_HOST=$(kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n knative-serving kourier -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
               kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
               kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
```
**What it means:** Try to find the external load balancer endpoint
**Why so many attempts:**
- Could be using Kourier (our setup) OR Istio
- Could get hostname (ALB) OR IP (NLB)
- Try all combinations until one works

**Fallback chain:**
1. Kourier hostname
2. Kourier IP
3. Istio hostname
4. Istio IP
5. Empty string (none found)

**Once we have both:** Can construct the full curl command:
```bash
curl -H "Host: $SERVICE_HOSTNAME" http://$INGRESS_HOST/invocations
```

**Why need Host header:**
- Load balancer handles many services
- Host header tells it which service you want
- Like telling receptionist which office you want to visit

---

## Common Bash Concepts Explained

### Variables

```bash
NAME="value"          # Create variable
echo $NAME            # Use variable
echo ${NAME}          # Use variable (explicit)
echo "${NAME}"        # Use variable (quoted, safer)
```

**Rules:**
- No spaces around `=`
- Use `$` to reference
- Quote to handle spaces in values

### Command Substitution

```bash
RESULT=$(command)     # Run command, save output
```

**Example:**
```bash
DATE=$(date)          # $DATE now contains current date
```

### Conditionals

```bash
if [ condition ]; then
    # do something
elif [ other_condition ]; then
    # do something else
else
    # default
fi
```

**Common tests:**
- `[ -f file ]` = file exists
- `[ -d dir ]` = directory exists
- `[ -n "$VAR" ]` = variable not empty
- `[ -z "$VAR" ]` = variable is empty
- `[ "$A" = "$B" ]` = strings equal
- `[[ $VAR =~ pattern ]]` = regex match

### Loops

```bash
# Counted loop
for i in {1..10}; do
    echo $i
done

# Loop over list
for item in apple orange banana; do
    echo $item
done

# While loop
while [ condition ]; do
    # do something
done
```

### Pipes and Redirects

```bash
command1 | command2        # Pipe: output of 1 to input of 2
command > file             # Redirect: output to file (overwrite)
command >> file            # Redirect: append to file
command 2> file            # Redirect: errors to file
command &> file            # Redirect: both output and errors
command >/dev/null         # Discard output
```

**Example:**
```bash
ls -l | grep ".txt"        # List files, filter for .txt
echo "hello" > file.txt    # Write to file
echo "world" >> file.txt   # Append to file
```

### Logical Operators

```bash
command1 && command2       # AND: run 2 only if 1 succeeds
command1 || command2       # OR: run 2 only if 1 fails
command1 ; command2        # Sequential: run both regardless
```

**Example:**
```bash
mkdir mydir && cd mydir    # Create and enter (only if mkdir works)
test -f file || touch file # Create file if doesn't exist
```

### Here Documents

```bash
cat <<EOF > file.txt
This is line 1
This is line 2
Variables like $VAR are expanded
EOF
```

**Variations:**
- `<<EOF` = expand variables
- `<<'EOF'` = don't expand variables (literal)
- `<<-EOF` = ignore leading tabs

### Exit Codes

```bash
command
echo $?                    # 0 = success, non-zero = error

exit 0                     # Exit script successfully
exit 1                     # Exit with error
```

**Using in conditions:**
```bash
if command; then           # If command succeeds
    echo "worked"
fi
```

### Arrays

```bash
ARRAY=(item1 item2 item3)  # Create array
echo ${ARRAY[0]}           # First item
echo ${ARRAY[@]}           # All items
echo ${#ARRAY[@]}          # Number of items
```

### Functions

```bash
function_name() {
    echo "argument 1: $1"
    echo "argument 2: $2"
    return 0
}

function_name arg1 arg2    # Call function
```

---

## Summary: Script Execution Order

**Full Setup (First Time):**
```
1. setup-eks-cluster.sh       (15-20 min) → Creates the foundation
2. setup-alb-controller.sh    (5 min)     → Adds front door
3. install-kserve.sh          (10 min)    → Adds model serving
4. setup-s3-mlflow.sh         (2 min)     → Adds storage + permissions
5. deploy-mlflow-on-eks.sh    (5 min)     → [Optional] MLflow in cluster
```

**Getting URL:**
```
get-inference-url.sh         → Shows how to access your model
```

**Cleanup:**
```
5-cleanup.sh                  (15-20 min) → Tears down everything
```

**If Something Fails:**
```
0-cleanup-failed-install.sh   (5 min)     → Clean partial install
Then retry from failed step
```

---

## 🎉 What's New? January 2026 Automation Improvements

### Summary of All Automation Added

The scripts have been significantly enhanced to automate everything that previously required manual intervention. Here's what changed:

#### 1. **Internet-Facing LoadBalancers (Script 3 & 6)**
**The Problem:**
- LoadBalancers were created as "internal" by default
- Services only accessible from within VPC
- Required manual AWS console changes

**The Solution:**
- Script 3 now auto-configures Kourier LoadBalancer as internet-facing
- Script 6 (MLflow deployment) uses internet-facing annotations
- Services are publicly accessible immediately

**What you see:**
```bash
✓ LoadBalancer is internet-facing (publicly accessible)
```

#### 2. **gp3 StorageClass Auto-Creation (Script 6)**
**The Problem:**
- EKS only has gp2 by default
- MLflow PVC failed with "StorageClass gp3 not found"
- Required manual StorageClass creation

**The Solution:**
- Script 6 checks for gp3 and creates it automatically
- Better performance: 3000 IOPS, 125 MB/s throughput
- More cost-effective than gp2

**What you see:**
```bash
✓ gp3 StorageClass created
```

#### 3. **boto3 Auto-Installation (MLflow Manifest)**
**The Problem:**
- Official MLflow image doesn't include boto3
- S3 artifact storage failed with "No module named 'boto3'"
- Required building custom Docker images

**The Solution:**
- Container startup command now includes: `pip install boto3 awscli mlflow`
- Works with official MLflow image
- Takes 30-40 seconds extra on first startup

**What you see:**
```bash
Successfully installed boto3-... awscli-... mlflow-...
```

#### 4. **Correct Hostnames (Test Scripts & Helper)**
**The Problem:**
- Scripts used main InferenceService URL (without `-predictor`)
- Resulted in 404 errors when calling endpoints
- Confusing for users

**The Solution:**
- All scripts now use predictor URL with `-predictor` suffix
- test_inference.sh and test_inference-mlserver.sh updated
- get-inference-url.sh shows correct URLs

**Before:** `mlflow-wine-classifier.namespace.example.com` ❌
**After:** `mlflow-wine-classifier-predictor.namespace.example.com` ✅

#### 5. **Correct Namespace Detection (get-inference-url.sh)**
**The Problem:**
- Script only checked `knative-serving` namespace
- Kourier is actually in `kourier-system` on our setup
- Failed to find LoadBalancer URL

**The Solution:**
- Checks `kourier-system` first (EKS setup)
- Falls back to `knative-serving` (other setups)
- Clear error messages if not found

#### 6. **Enhanced Cleanup (Script 6-cleanup.sh)**
**The Problem:**
- gp3 StorageClass wasn't being deleted
- Orphaned LoadBalancers not detected properly

**The Solution:**
- Now deletes gp3 StorageClass
- Better orphaned resource detection
- Improved error handling and messages

### Before vs After Comparison

| Issue | Before (Manual) | After (Automated) |
|-------|----------------|-------------------|
| **LoadBalancer Access** | Edit AWS console to make internet-facing | ✅ Auto-configured as internet-facing |
| **gp3 Storage** | Manually create StorageClass | ✅ Auto-created if missing |
| **boto3 for S3** | Build custom Docker image | ✅ Auto-installed on container start |
| **Endpoint URLs** | Manually fix hostname in scripts | ✅ Correct predictor URL used |
| **Finding Kourier** | Check multiple namespaces manually | ✅ Auto-checks correct namespace |
| **Cleanup** | Manually delete gp3, check for orphans | ✅ Automated deletion and detection |

### What This Means for You

**As a new user:**
- Just run scripts 1-4 in sequence
- Everything works automatically
- No troubleshooting needed
- Services accessible immediately

**As an existing user:**
- See [KEY_CHANGES_SUMMARY.md](KEY_CHANGES_SUMMARY.md) for migration steps
- Delete and recreate LoadBalancer services to make them internet-facing
- Update test scripts to latest versions

### Verification Checklist

After running the setup, verify everything is configured correctly:

```bash
# 1. Check gp3 exists
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

# 4. Test inference endpoint
./test_inference.sh
# Expected: ✓ Success! HTTP Status: 200
```

---

## Tips for Beginners

### 1. Read Error Messages

Don't panic! Error messages usually tell you what's wrong:
```
Error: file not found
```
→ The file you're looking for doesn't exist

```
Error: permission denied
```
→ You don't have permission (try sudo or check AWS IAM)

### 2. Use `-h` or `--help`

Most commands have help:
```bash
kubectl --help
aws s3 help
```

### 3. Check Status Often

```bash
kubectl get pods -A           # See all pods
kubectl get svc -A            # See all services
kubectl describe pod <name>   # Detailed info
kubectl logs <pod>            # See logs
```

### 4. Things Take Time

- EKS cluster creation: 15-20 minutes
- Pod startup (first time): 2-5 minutes (pulling images)
- Load balancer provisioning: 2-3 minutes

**Be patient!**

### 5. Use Tab Completion

Type partial command and press Tab:
```bash
kube<TAB>       → kubectl
kubectl get po<TAB>  → kubectl get pods
```

### 6. Keep a Terminal Log

```bash
script my-session.log   # Start logging
# ... do your work ...
exit                     # Stop logging
```

Now you have a record of everything!

### 7. Bookmark Important URLs

- AWS Console: https://console.aws.amazon.com
- Kubernetes Docs: https://kubernetes.io/docs
- KServe Docs: https://kserve.github.io/website

---

## Final Words

**Don't memorize everything!** This guide is for reference.

**Key concepts to understand:**
1. Scripts run commands automatically
2. Each command does one thing
3. Commands are chained together for complex tasks
4. Errors are normal - read and learn from them
5. Always have backups before cleanup

**Practice makes perfect!** Run through the setup a few times to understand the flow.

---

**Last Updated:** January 2025

Questions? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.
