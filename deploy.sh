#!/bin/bash
set -euo pipefail

export AWS_REGION="eu-central-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
STATE_BUCKET="anagram-tfstate-${ACCOUNT_ID}"

echo "======================================"
echo " 🚀 STARTING LOCAL DEPLOYMENT"
echo "======================================"

# 1. Ensure State Bucket Exists
echo "▶ 1. Checking Terraform State Bucket..."
aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || \
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || true

# 2. Login to ECR
echo "▶ 2. Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 3. Build and Push Images
echo "▶ 3. Building and Pushing Images..."
docker build -t $ECR_REGISTRY/anagram-backend:latest ./backend
docker push $ECR_REGISTRY/anagram-backend:latest

docker build -t $ECR_REGISTRY/anagram-frontend:latest ./frontend
docker push $ECR_REGISTRY/anagram-frontend:latest

docker build -t $ECR_REGISTRY/anagram-nginx:latest ./nginx
docker push $ECR_REGISTRY/anagram-nginx:latest

# 4. Run Terraform
echo "▶ 4. Running Terraform..."
cd terraform
terraform init -reconfigure -backend-config="bucket=$STATE_BUCKET"
terraform apply -auto-approve

echo "======================================"
echo " ✅ DEPLOYMENT SUCCESSFUL!"
echo " Waiting 3 minutes for EC2s to boot..."
echo "======================================"