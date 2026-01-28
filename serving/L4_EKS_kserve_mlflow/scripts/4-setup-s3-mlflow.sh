#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}S3 and MLflow Setup for EKS${NC}"
echo -e "${GREEN}========================================${NC}"

# Variables
BUCKET_NAME="kserve-mlflow-artifacts-$(aws sts get-caller-identity --query Account --output text)"
REGION="us-east-1"
CLUSTER_NAME="kserve-mlflow-cluster"

echo -e "\n${YELLOW}Creating S3 bucket for MLflow artifacts...${NC}"

# Create S3 bucket
if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION
    echo -e "${GREEN}✓ S3 bucket created: $BUCKET_NAME${NC}"
else
    echo -e "${YELLOW}Bucket already exists: $BUCKET_NAME${NC}"
fi

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

echo -e "${GREEN}✓ Versioning enabled${NC}"

# Create IAM policy for S3 access
echo -e "\n${YELLOW}Creating IAM policy for S3 access...${NC}"

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

POLICY_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/KServeS3AccessPolicy"

# Check if policy exists
if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo -e "${YELLOW}Policy already exists${NC}"
    # Update the policy
    POLICY_VERSION=$(aws iam create-policy-version \
        --policy-arn $POLICY_ARN \
        --policy-document file://s3-policy.json \
        --set-as-default \
        --query 'PolicyVersion.VersionId' \
        --output text)
    echo -e "${GREEN}✓ Policy updated (version: $POLICY_VERSION)${NC}"
else
    aws iam create-policy \
        --policy-name KServeS3AccessPolicy \
        --policy-document file://s3-policy.json
    echo -e "${GREEN}✓ IAM policy created${NC}"
fi

# Create service account with IAM role for KServe pods
echo -e "\n${YELLOW}Creating IAM service account for KServe...${NC}"
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=mlflow-kserve-test \
    --name=kserve-sa \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --approve

# Cleanup
rm -f s3-policy.json

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ S3 and IAM Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nS3 Bucket: $BUCKET_NAME"
echo -e "Service Account: kserve-sa (in mlflow-kserve-test namespace)"
echo -e "\nTo use this in your InferenceService, add the following to your YAML:"
echo -e "  serviceAccountName: kserve-sa"
echo -e "\nFor MLflow tracking server, set:"
echo -e "  export MLFLOW_TRACKING_URI=<your-mlflow-server-url>"
echo -e "  export MLFLOW_S3_BUCKET=$BUCKET_NAME"
