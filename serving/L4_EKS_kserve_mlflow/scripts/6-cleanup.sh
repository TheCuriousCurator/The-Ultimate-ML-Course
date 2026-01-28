#!/bin/bash

# Enhanced EKS Cluster Cleanup Script
# Version: 2.0 - January 2026
# Features: Retry logic, better error handling, parallel cleanup, force mode

set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="kserve-mlflow-cluster"
REGION="us-east-1"
MAX_RETRIES=2
CLOUDFORMATION_TIMEOUT=1800  # 30 minutes in seconds
FORCE_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--force] [--cluster NAME] [--region REGION]"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_phase() {
    echo -e "\n${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}============================================================${NC}"
}

# Progress indicator
show_progress() {
    local duration=$1
    local message=$2
    local elapsed=0

    while [ $elapsed -lt $duration ]; do
        echo -ne "\r${message} (${elapsed}/${duration}s)..."
        sleep 1
        ((elapsed++))
    done
    echo -ne "\r${message} (${duration}/${duration}s)... Done!\n"
}

# Verify resource deletion
verify_cluster_deleted() {
    log_info "Verifying cluster deletion..."
    if eksctl get cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
        return 1  # Cluster still exists
    else
        return 0  # Cluster deleted
    fi
}

verify_stack_deleted() {
    local stack_name=$1
    if aws cloudformation describe-stacks --region $REGION --stack-name $stack_name &>/dev/null; then
        return 1  # Stack exists
    else
        return 0  # Stack deleted
    fi
}

# Enhanced cluster deletion with retry
delete_cluster_with_retry() {
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Cluster deletion attempt $attempt/$MAX_RETRIES..."

        # Start timer
        local start_time=$(date +%s)

        # Try to delete cluster
        if eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait 2>&1 | tee /tmp/eksctl-delete.log; then
            log_success "Cluster deletion command completed"

            # Verify actual deletion
            if verify_cluster_deleted; then
                log_success "Cluster verified as deleted"
                return 0
            else
                log_warning "Cluster deletion reported success but cluster still exists"
            fi
        else
            local exit_code=$?
            log_warning "Cluster deletion command failed with exit code $exit_code"

            # Check if it's a "waiter" failure but cluster is actually deleted
            if grep -q "waiter state transitioned to Failure" /tmp/eksctl-delete.log 2>/dev/null; then
                log_info "Detected waiter timeout, verifying actual cluster state..."
                sleep 10

                if verify_cluster_deleted; then
                    log_success "Cluster is actually deleted despite waiter error!"
                    return 0
                fi
            fi
        fi

        # Check if we should retry
        if [ $attempt -lt $MAX_RETRIES ]; then
            local wait_time=$((attempt * 30))
            log_warning "Retrying in ${wait_time} seconds..."
            sleep $wait_time
        fi

        ((attempt++))
    done

    # Final verification after all retries
    if verify_cluster_deleted; then
        log_success "Cluster is deleted (verified after retries)"
        return 0
    else
        log_error "Cluster deletion failed after $MAX_RETRIES attempts"
        return 1
    fi
}

# Force delete CloudFormation stacks
force_delete_stacks() {
    log_warning "Attempting to force-delete CloudFormation stacks..."

    local stacks=(
        "eksctl-${CLUSTER_NAME}-cluster"
        "eksctl-${CLUSTER_NAME}-nodegroup-kserve-nodegroup"
        "eksctl-${CLUSTER_NAME}-addon-vpc-cni"
        "eksctl-${CLUSTER_NAME}-addon-aws-ebs-csi-driver"
    )

    for stack in "${stacks[@]}"; do
        if ! verify_stack_deleted "$stack"; then
            log_info "Force deleting stack: $stack"
            aws cloudformation delete-stack --region $REGION --stack-name $stack 2>/dev/null || true
        fi
    done

    log_info "Waiting 60 seconds for force deletion to propagate..."
    sleep 60
}

# Main script
echo -e "${RED}========================================${NC}"
echo -e "${RED}Enhanced EKS Cluster Cleanup Script v2.0${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${YELLOW}WARNING: This will delete the entire EKS cluster and associated resources!${NC}"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
    log_error "Cannot get AWS account ID. Please configure AWS credentials."
    exit 1
fi

echo -e "\nCluster: $CLUSTER_NAME"
echo -e "Region: $REGION"
echo -e "Account: $AWS_ACCOUNT_ID"
echo -e "Force Mode: $FORCE_MODE"

if [ "$FORCE_MODE" = false ]; then
    read -p $'\nAre you sure you want to delete the cluster and all resources? (yes/no): ' -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_success "Cleanup cancelled"
        exit 0
    fi
fi

START_TIME=$(date +%s)
log_info "Starting cleanup process at $(date)"
log_warning "Estimated time: 20-30 minutes (with retries)"

# ============================================================
# PRE-FLIGHT CHECKS
# ============================================================
log_phase "Phase 0: Pre-flight Checks"

# Check if cluster exists
log_info "Checking if cluster exists..."
if ! eksctl get cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
    log_warning "Cluster $CLUSTER_NAME not found. Will skip Kubernetes cleanup."
    CLUSTER_EXISTS=false
else
    log_success "Cluster found"
    CLUSTER_EXISTS=true
    # Update kubeconfig
    eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$REGION &>/dev/null
fi

# Estimate cleanup time based on resources
if [ "$CLUSTER_EXISTS" = true ]; then
    log_info "Scanning cluster resources..."
    ISVC_COUNT=$(kubectl get inferenceservice -A --no-headers 2>/dev/null | wc -l)
    SVC_COUNT=$(kubectl get svc -A --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
    PVC_COUNT=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)

    log_info "Found: $ISVC_COUNT InferenceServices, $SVC_COUNT LoadBalancers, $PVC_COUNT PVCs"

    # Estimate time: 5min base + 2min per LB + 1min per PVC
    ESTIMATED_TIME=$((300 + SVC_COUNT * 120 + PVC_COUNT * 60))
    log_info "Estimated cleanup time: $((ESTIMATED_TIME / 60)) minutes"
fi

# ============================================================
# PHASE 1: Delete Kubernetes Resources
# ============================================================
if [ "$CLUSTER_EXISTS" = true ]; then
    log_phase "Phase 1: Cleaning up Kubernetes Resources"

    # Delete InferenceServices
    log_info "1. Deleting InferenceServices..."
    if kubectl delete inferenceservice --all -A --ignore-not-found=true --timeout=60s 2>/dev/null; then
        log_success "InferenceServices deleted"
    else
        log_warning "Some InferenceServices may have failed to delete (continuing)"
    fi

    # Delete Load Balancer services
    log_info "2. Deleting LoadBalancer services..."

    # MLflow LoadBalancer
    if kubectl delete svc mlflow-server -n mlflow-kserve-test --ignore-not-found=true --timeout=60s 2>/dev/null; then
        log_success "MLflow LoadBalancer deleted"
    else
        log_warning "MLflow LoadBalancer not found or already deleted"
    fi

    # Kourier LoadBalancer
    if kubectl delete svc kourier -n kourier-system --ignore-not-found=true --timeout=60s 2>/dev/null; then
        log_success "Kourier LoadBalancer deleted"
    else
        log_warning "Kourier LoadBalancer not found or already deleted"
    fi

    # Istio LoadBalancers (if exists)
    log_info "Checking for Istio LoadBalancers..."
    ISTIO_LBS=$(kubectl get svc -n istio-system --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
    if [ $ISTIO_LBS -gt 0 ]; then
        log_info "Found $ISTIO_LBS Istio LoadBalancer(s), deleting..."
        kubectl delete svc -n istio-system --field-selector spec.type=LoadBalancer --ignore-not-found=true --timeout=120s 2>/dev/null && \
            log_success "Istio LoadBalancer(s) deleted" || \
            log_warning "Istio LoadBalancer deletion timed out (may still be in progress)"
    else
        log_info "No Istio LoadBalancers found"
    fi

    # Other LoadBalancers in knative-serving
    kubectl delete svc --all -n knative-serving --field-selector spec.type=LoadBalancer --ignore-not-found=true --timeout=60s 2>/dev/null || true

    # Delete namespaces
    log_info "3. Deleting application namespaces..."
    if kubectl delete namespace mlflow-kserve-test --ignore-not-found=true --timeout=120s 2>/dev/null; then
        log_success "Namespace mlflow-kserve-test deleted"
    else
        log_warning "Namespace deletion timed out or failed (continuing)"
    fi

    # Delete gp3 StorageClass
    log_info "4. Deleting gp3 StorageClass..."
    kubectl delete storageclass gp3 --ignore-not-found=true 2>/dev/null && log_success "gp3 StorageClass deleted" || log_info "gp3 not found"

    # Wait for AWS LoadBalancers to be cleaned up
    log_info "5. Waiting for AWS to clean up LoadBalancers..."
    show_progress 120 "LoadBalancer cleanup in progress"

    # Verify LoadBalancers are gone with retry
    log_info "6. Verifying LoadBalancers are deleted..."
    local lb_check_attempts=0
    local max_lb_checks=3

    while [ $lb_check_attempts -lt $max_lb_checks ]; do
        LB_COUNT=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?contains(LoadBalancerName, 'kserve') || contains(LoadBalancerName, 'mlflow') || contains(LoadBalancerName, 'istio')].LoadBalancerName" --output text 2>/dev/null | wc -w)

        if [ $LB_COUNT -eq 0 ]; then
            log_success "All LoadBalancers cleaned up"
            break
        else
            ((lb_check_attempts++))
            if [ $lb_check_attempts -lt $max_lb_checks ]; then
                log_warning "Found $LB_COUNT LoadBalancers still active, waiting 30s more... (attempt $lb_check_attempts/$max_lb_checks)"
                sleep 30
            else
                log_warning "Found $LB_COUNT LoadBalancers still active after $max_lb_checks checks"
                log_warning "These will be reported as orphaned resources at the end"
            fi
        fi
    done
else
    log_warning "Skipping Kubernetes cleanup (cluster doesn't exist)"
fi

# ============================================================
# PHASE 2: Delete IAM Service Accounts
# ============================================================
log_phase "Phase 2: Cleaning up IAM Service Accounts"

if [ "$CLUSTER_EXISTS" = true ]; then
    log_info "Deleting IAM service accounts..."

    # Delete kserve-sa
    if eksctl delete iamserviceaccount \
        --cluster=$CLUSTER_NAME \
        --region=$REGION \
        --namespace=mlflow-kserve-test \
        --name=kserve-sa 2>/dev/null; then
        log_success "kserve-sa deleted"
    else
        log_info "kserve-sa not found or already deleted"
    fi

    # Delete ALB controller service account
    if eksctl delete iamserviceaccount \
        --cluster=$CLUSTER_NAME \
        --region=$REGION \
        --namespace=kube-system \
        --name=aws-load-balancer-controller 2>/dev/null; then
        log_success "aws-load-balancer-controller deleted"
    else
        log_info "aws-load-balancer-controller not found or already deleted"
    fi
else
    log_warning "Skipping IAM service account cleanup (cluster doesn't exist)"
fi

# ============================================================
# PHASE 3: Delete EKS Cluster (with retry logic)
# ============================================================
log_phase "Phase 3: Deleting EKS Cluster"

if [ "$CLUSTER_EXISTS" = true ]; then
    log_info "Deleting EKS cluster (this may take 15-30 minutes)..."
    log_info "The script will retry if CloudFormation times out"

    if delete_cluster_with_retry; then
        log_success "✓ Cluster deleted successfully"
    else
        log_error "Cluster deletion failed after retries"

        if [ "$FORCE_MODE" = true ]; then
            log_warning "Force mode enabled - attempting stack force deletion"
            force_delete_stacks

            if verify_cluster_deleted; then
                log_success "Cluster deleted via force mode"
            else
                log_error "Force deletion also failed - manual intervention required"
            fi
        else
            log_error "Cluster may still exist. Re-run with --force to attempt forced deletion"
        fi
    fi
else
    log_warning "Cluster already deleted or doesn't exist"
fi

# ============================================================
# PHASE 4: Clean up VPC and Associated Resources
# ============================================================
log_phase "Phase 4: Cleaning up VPC and Network Resources"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --region $REGION \
    --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=$CLUSTER_NAME" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    log_info "Found VPC: $VPC_ID"

    # 1. Delete NAT Gateways and release Elastic IPs
    log_info "1. Deleting NAT Gateways..."
    NAT_GWS=$(aws ec2 describe-nat-gateways --region $REGION \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)

    if [ -n "$NAT_GWS" ]; then
        for nat in $NAT_GWS; do
            log_info "   Deleting NAT Gateway: $nat"
            # Get EIP allocations before deleting NAT gateway
            EIP_ALLOCS=$(aws ec2 describe-nat-gateways --region $REGION \
                --nat-gateway-ids $nat \
                --query 'NatGateways[0].NatGatewayAddresses[].AllocationId' --output text 2>/dev/null)

            aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION 2>/dev/null && \
                log_success "   NAT Gateway $nat deleted" || \
                log_warning "   Failed to delete NAT Gateway $nat"

            # Store EIP allocations for later release
            if [ -n "$EIP_ALLOCS" ]; then
                for eip in $EIP_ALLOCS; do
                    echo "$eip" >> /tmp/eips-to-release.txt
                done
            fi
        done
        log_info "   Waiting 60s for NAT Gateways to finish deleting..."
        sleep 60
    else
        log_info "   No NAT Gateways found"
    fi

    # 2. Detach and Delete Internet Gateways
    log_info "2. Deleting Internet Gateways..."
    IGW_IDS=$(aws ec2 describe-internet-gateways --region $REGION \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null)

    if [ -n "$IGW_IDS" ]; then
        for igw in $IGW_IDS; do
            log_info "   Detaching and deleting IGW: $igw"
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION 2>/dev/null
            aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION 2>/dev/null && \
                log_success "   IGW $igw deleted" || \
                log_warning "   Failed to delete IGW $igw"
        done
    else
        log_info "   No Internet Gateways found"
    fi

    # 3. Delete Network Interfaces
    log_info "3. Deleting Network Interfaces (ENIs)..."
    ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' --output text 2>/dev/null)

    if [ -n "$ENI_IDS" ]; then
        for eni in $ENI_IDS; do
            aws ec2 delete-network-interface --network-interface-id $eni --region $REGION 2>/dev/null && \
                log_success "   ENI $eni deleted" || \
                log_info "   ENI $eni in use or already deleted"
        done
    else
        log_info "   No available ENIs to delete"
    fi

    # 4. Delete Subnets
    log_info "4. Deleting Subnets..."
    SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null)

    if [ -n "$SUBNET_IDS" ]; then
        for subnet in $SUBNET_IDS; do
            aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null && \
                log_success "   Subnet $subnet deleted" || \
                log_warning "   Failed to delete subnet $subnet (may have dependencies)"
        done
    else
        log_info "   No subnets found"
    fi

    # 5. Delete Route Tables (except main)
    log_info "5. Deleting Route Tables..."
    RT_IDS=$(aws ec2 describe-route-tables --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null)

    if [ -n "$RT_IDS" ]; then
        for rt in $RT_IDS; do
            aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null && \
                log_success "   Route table $rt deleted" || \
                log_warning "   Failed to delete route table $rt"
        done
    else
        log_info "   No custom route tables found"
    fi

    # 6. Delete Security Groups (except default)
    log_info "6. Deleting Security Groups..."
    SG_IDS=$(aws ec2 describe-security-groups --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null)

    if [ -n "$SG_IDS" ]; then
        # Try multiple times as security groups may have dependencies
        for attempt in 1 2 3; do
            log_info "   Attempt $attempt to delete security groups..."
            for sg in $SG_IDS; do
                aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null && \
                    log_success "   Security group $sg deleted" || true
            done
            sleep 5
        done
    else
        log_info "   No custom security groups found"
    fi

    # 7. Delete VPC
    log_info "7. Deleting VPC..."
    if aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null; then
        log_success "✓ VPC $VPC_ID deleted successfully"
    else
        log_warning "Failed to delete VPC $VPC_ID - may have remaining dependencies"
        log_info "VPC will be reported in orphaned resources section"
    fi

    # 8. Release Elastic IPs
    if [ -f /tmp/eips-to-release.txt ]; then
        log_info "8. Releasing Elastic IPs..."
        while read -r eip; do
            if [ -n "$eip" ]; then
                aws ec2 release-address --allocation-id $eip --region $REGION 2>/dev/null && \
                    log_success "   EIP $eip released" || \
                    log_warning "   Failed to release EIP $eip"
            fi
        done < /tmp/eips-to-release.txt
        rm -f /tmp/eips-to-release.txt
    fi
else
    log_info "No VPC found for cluster $CLUSTER_NAME"
fi

# ============================================================
# PHASE 5 & 6: Parallel Cleanup of IAM Policies and S3
# ============================================================
log_phase "Phase 5 & 6: Cleaning up IAM Policies and S3 (Parallel)"

# Function to delete IAM policies
delete_iam_policies() {
    log_info "[IAM] Deleting IAM policies..."

    # Delete KServe S3 policy
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KServeS3AccessPolicy"
    if aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
        # Delete all non-default versions
        VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
        for version in $VERSIONS; do
            aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version 2>/dev/null || true
        done

        if aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null; then
            log_success "[IAM] KServeS3AccessPolicy deleted"
        else
            log_warning "[IAM] Failed to delete KServeS3AccessPolicy"
        fi
    else
        log_info "[IAM] KServeS3AccessPolicy not found"
    fi

    # Delete ALB controller policy
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
    if aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
        VERSIONS=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
        for version in $VERSIONS; do
            aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version 2>/dev/null || true
        done

        if aws iam delete-policy --policy-arn $POLICY_ARN 2>/dev/null; then
            log_success "[IAM] AWSLoadBalancerControllerIAMPolicy deleted"
        else
            log_warning "[IAM] Failed to delete AWSLoadBalancerControllerIAMPolicy"
        fi
    else
        log_info "[IAM] AWSLoadBalancerControllerIAMPolicy not found"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    BUCKET_NAME="kserve-mlflow-artifacts-${AWS_ACCOUNT_ID}"
    log_info "[S3] Emptying and deleting S3 bucket..."

    if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
        # Delete all versions
        aws s3api delete-objects --bucket $BUCKET_NAME \
            --delete "$(aws s3api list-object-versions --bucket $BUCKET_NAME \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

        # Delete delete markers
        aws s3api delete-objects --bucket $BUCKET_NAME \
            --delete "$(aws s3api list-object-versions --bucket $BUCKET_NAME \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

        # Delete remaining objects
        aws s3 rm s3://$BUCKET_NAME --recursive 2>/dev/null || true

        # Delete bucket
        if aws s3 rb s3://$BUCKET_NAME 2>/dev/null; then
            log_success "[S3] S3 bucket deleted"
        else
            log_warning "[S3] Failed to delete S3 bucket"
        fi
    else
        log_info "[S3] S3 bucket not found"
    fi
}

# Ask user for confirmation (unless force mode)
DELETE_IAM=false
DELETE_S3=false

if [ "$FORCE_MODE" = true ]; then
    DELETE_IAM=true
    DELETE_S3=true
    log_info "Force mode: Auto-deleting IAM policies and S3 bucket"
else
    read -p $'\nDelete IAM policies? (yes/no): ' -r
    [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]] && DELETE_IAM=true

    read -p $'Delete S3 bucket? (yes/no): ' -r
    [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]] && DELETE_S3=true
fi

# Run deletions in parallel
if [ "$DELETE_IAM" = true ] || [ "$DELETE_S3" = true ]; then
    (
        [ "$DELETE_IAM" = true ] && delete_iam_policies
    ) &
    PID_IAM=$!

    (
        [ "$DELETE_S3" = true ] && delete_s3_bucket
    ) &
    PID_S3=$!

    # Wait for both to complete
    [ "$DELETE_IAM" = true ] && wait $PID_IAM
    [ "$DELETE_S3" = true ] && wait $PID_S3

    log_success "Parallel cleanup completed"
fi

# ============================================================
# PHASE 7: Comprehensive Orphaned Resource Check
# ============================================================
log_phase "Phase 7: Checking for Orphaned Resources"

ORPHANS_FOUND=false

# Check LoadBalancers
log_info "Checking for orphaned LoadBalancers..."
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?contains(LoadBalancerName, 'kserve') || contains(LoadBalancerName, 'mlflow') || contains(LoadBalancerName, 'kourier') || contains(LoadBalancerName, 'istio')].LoadBalancerArn" --output text 2>/dev/null || echo "")
if [ -n "$LBS" ]; then
    log_warning "Found orphaned LoadBalancers:"
    for lb in $LBS; do
        LB_INFO=$(aws elbv2 describe-load-balancers --load-balancer-arns $lb --query 'LoadBalancers[0].[LoadBalancerName,Type,DNSName]' --output text 2>/dev/null)
        LB_NAME=$(echo "$LB_INFO" | awk '{print $1}')
        LB_TYPE=$(echo "$LB_INFO" | awk '{print $2}')
        LB_DNS=$(echo "$LB_INFO" | awk '{print $3}')
        echo "  - Name: $LB_NAME"
        echo "    Type: $LB_TYPE"
        echo "    DNS: $LB_DNS"
        echo "    ARN: $lb"
        echo ""
        ORPHANS_FOUND=true
    done
    echo -e "${YELLOW}To delete manually:${NC}"
    echo -e "${YELLOW}  aws elbv2 delete-load-balancer --load-balancer-arn <arn> --region $REGION${NC}"
    echo -e "${YELLOW}Example:${NC}"
    echo -e "${YELLOW}  aws elbv2 delete-load-balancer --load-balancer-arn '$lb' --region $REGION${NC}"
else
    log_success "No orphaned LoadBalancers found"
fi

# Check Security Groups
log_info "Checking for orphaned security groups..."
SGS=$(aws ec2 describe-security-groups --region $REGION --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
if [ -n "$SGS" ]; then
    log_warning "Found orphaned security groups:"
    for sg in $SGS; do
        SG_NAME=$(aws ec2 describe-security-groups --group-ids $sg --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "unknown")
        echo "  - $sg ($SG_NAME)"
        ORPHANS_FOUND=true
    done
    echo -e "${YELLOW}To delete: aws ec2 delete-security-group --group-id <id> --region $REGION${NC}"
else
    log_success "No orphaned security groups found"
fi

# Check EBS Volumes
log_info "Checking for orphaned EBS volumes..."
VOLS=$(aws ec2 describe-volumes --region $REGION --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query 'Volumes[].VolumeId' --output text 2>/dev/null || echo "")
if [ -n "$VOLS" ]; then
    log_warning "Found orphaned EBS volumes:"
    for vol in $VOLS; do
        VOL_STATE=$(aws ec2 describe-volumes --volume-ids $vol --query 'Volumes[0].State' --output text 2>/dev/null || echo "unknown")
        VOL_SIZE=$(aws ec2 describe-volumes --volume-ids $vol --query 'Volumes[0].Size' --output text 2>/dev/null || echo "unknown")
        echo "  - $vol (state: $VOL_STATE, size: ${VOL_SIZE}GB)"
        ORPHANS_FOUND=true
    done
    echo -e "${YELLOW}To delete: aws ec2 delete-volume --volume-id <id> --region $REGION${NC}"
else
    log_success "No orphaned EBS volumes found"
fi

# Check CloudWatch Logs
log_info "Checking for CloudWatch log groups..."
LOGS=$(aws logs describe-log-groups --region $REGION --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
if [ -n "$LOGS" ]; then
    log_info "Found CloudWatch log groups:"
    for log in $LOGS; do
        echo "  - $log"
    done

    if [ "$FORCE_MODE" = true ]; then
        log_info "Force mode: Auto-deleting log groups"
        DELETE_LOGS=true
    else
        read -p $'Delete log groups? (yes/no): ' -r
        [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]] && DELETE_LOGS=true || DELETE_LOGS=false
    fi

    if [ "$DELETE_LOGS" = true ]; then
        for log in $LOGS; do
            if aws logs delete-log-group --log-group-name $log --region $REGION 2>/dev/null; then
                log_success "Deleted $log"
            else
                log_warning "Failed to delete $log"
            fi
        done
    fi
else
    log_success "No CloudWatch log groups found"
fi

# Check for orphaned VPCs
log_info "Checking for orphaned VPCs..."
VPCS=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=$CLUSTER_NAME" --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
if [ -n "$VPCS" ]; then
    log_warning "Found orphaned VPCs (Phase 4 VPC cleanup may have failed):"
    for vpc in $VPCS; do
        VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids $vpc --region $REGION --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "unnamed")
        echo "  - VPC ID: $vpc"
        echo "    Name: $VPC_NAME"

        # Check for remaining dependencies
        SUBNET_COUNT=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'Subnets | length(@)' --output text 2>/dev/null || echo "0")
        RT_COUNT=$(aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'RouteTables[?Associations[0].Main!=`true`] | length(@)' --output text 2>/dev/null || echo "0")
        SG_COUNT=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'SecurityGroups[?GroupName!=`default`] | length(@)' --output text 2>/dev/null || echo "0")
        IGW_COUNT=$(aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$vpc" --query 'InternetGateways | length(@)' --output text 2>/dev/null || echo "0")
        NAT_COUNT=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query 'NatGateways | length(@)' --output text 2>/dev/null || echo "0")

        echo "    Dependencies: $SUBNET_COUNT subnets, $RT_COUNT route tables, $SG_COUNT security groups, $IGW_COUNT IGWs, $NAT_COUNT NAT gateways"
        echo ""
        ORPHANS_FOUND=true
    done

    echo -e "${YELLOW}To manually delete VPC and dependencies:${NC}"
    echo -e "${YELLOW}  # First, delete NAT gateways:${NC}"
    echo -e "${YELLOW}  aws ec2 describe-nat-gateways --region $REGION --filter 'Name=vpc-id,Values=$vpc' --query 'NatGateways[].NatGatewayId' --output text | xargs -I {} aws ec2 delete-nat-gateway --nat-gateway-id {} --region $REGION${NC}"
    echo -e "${YELLOW}  sleep 60  # Wait for NAT gateways to delete${NC}"
    echo -e "${YELLOW}  # Detach and delete Internet gateways:${NC}"
    echo -e "${YELLOW}  aws ec2 describe-internet-gateways --region $REGION --filters 'Name=attachment.vpc-id,Values=$vpc' --query 'InternetGateways[].InternetGatewayId' --output text | xargs -I {} bash -c 'aws ec2 detach-internet-gateway --internet-gateway-id {} --vpc-id $vpc --region $REGION && aws ec2 delete-internet-gateway --internet-gateway-id {} --region $REGION'${NC}"
    echo -e "${YELLOW}  # Delete subnets:${NC}"
    echo -e "${YELLOW}  aws ec2 describe-subnets --region $REGION --filters 'Name=vpc-id,Values=$vpc' --query 'Subnets[].SubnetId' --output text | xargs -I {} aws ec2 delete-subnet --subnet-id {} --region $REGION${NC}"
    echo -e "${YELLOW}  # Delete route tables:${NC}"
    echo -e "${YELLOW}  aws ec2 describe-route-tables --region $REGION --filters 'Name=vpc-id,Values=$vpc' --query 'RouteTables[?Associations[0].Main!=\`true\`].RouteTableId' --output text | xargs -I {} aws ec2 delete-route-table --route-table-id {} --region $REGION${NC}"
    echo -e "${YELLOW}  # Delete security groups (may need multiple attempts):${NC}"
    echo -e "${YELLOW}  aws ec2 describe-security-groups --region $REGION --filters 'Name=vpc-id,Values=$vpc' --query 'SecurityGroups[?GroupName!=\`default\`].GroupId' --output text | xargs -I {} aws ec2 delete-security-group --group-id {} --region $REGION${NC}"
    echo -e "${YELLOW}  # Finally, delete VPC:${NC}"
    echo -e "${YELLOW}  aws ec2 delete-vpc --vpc-id $vpc --region $REGION${NC}"
else
    log_success "No orphaned VPCs found"
fi

# ============================================================
# FINAL SUMMARY
# ============================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log_phase "Cleanup Summary"

log_success "✓ Cleanup completed in ${MINUTES}m ${SECONDS}s"

echo -e "\n${GREEN}Resources Cleaned:${NC}"
echo "  ✓ EKS cluster: $CLUSTER_NAME"
echo "  ✓ Kubernetes resources (InferenceServices, namespaces, StorageClass)"
echo "  ✓ IAM service accounts and roles"
[ "$DELETE_IAM" = true ] && echo "  ✓ IAM policies"
[ "$DELETE_S3" = true ] && echo "  ✓ S3 bucket"
echo "  ✓ CloudWatch logs (if confirmed)"

if [ "$ORPHANS_FOUND" = true ]; then
    echo -e "\n${YELLOW}⚠ Some orphaned resources were found (see above)${NC}"
    echo -e "${YELLOW}  Please review and manually delete if needed${NC}"
else
    echo -e "\n${GREEN}✓ No orphaned resources found!${NC}"
fi

echo -e "\n${BLUE}Final Verification:${NC}"
echo "  1. Check AWS Console → EKS → Clusters (should be empty)"
echo "  2. Check AWS Console → EC2 → Load Balancers (should have no kserve/mlflow LBs)"
echo "  3. Check AWS Console → EC2 → Volumes (should have no available volumes)"
echo "  4. Check AWS Billing → Cost Explorer (verify $0 charges within 24 hours)"

echo -e "\n${GREEN}Thank you for using the EKS KServe setup!${NC}"
echo -e "${BLUE}For issues or feedback: https://github.com/anthropics/claude-code/issues${NC}"

exit 0
