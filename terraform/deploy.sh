#!/bin/bash
set -euo pipefail

# Auto-navigate to the project root
if [ -d "terraform" ]; then
  : # already in root
elif [ -d "../terraform" ]; then
  cd ..
else
  echo "❌ Cannot find terraform/ directory. Please run from the project root."
  exit 1
fi

export AWS_REGION="eu-central-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
STATE_BUCKET="anagram-tfstate-${ACCOUNT_ID}"
CODE_HASH=$(find backend frontend nginx -type f -not -path '*/node_modules/*' \
  | sort | xargs sha256sum | sha256sum | awk '{print $1}')

echo "======================================"
echo " 🚀 STARTING LOCAL DEPLOYMENT"
echo "======================================"

# 1. Ensure State Bucket Exists
echo "▶ 1. Checking Terraform State Bucket..."
aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || \
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || true

# 2. Initialize Terraform
echo "▶ 2. Initializing Terraform..."
cd terraform
terraform init -reconfigure -backend-config="bucket=$STATE_BUCKET"

# 3. Create ECR and S3 Infrastructure FIRST
echo "▶ 3. Provisioning ECR Repositories and Artifact Bucket..."
terraform apply -auto-approve -target=module.ecr -target=module.artifact
cd ..

# 4. Login to ECR & Build Images
echo "▶ 4. Logging into ECR and Building Images..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

docker build -t $ECR_REGISTRY/anagram-backend:latest ./backend
docker push $ECR_REGISTRY/anagram-backend:latest

docker build -t $ECR_REGISTRY/anagram-frontend:latest ./frontend
docker push $ECR_REGISTRY/anagram-frontend:latest

docker build -t $ECR_REGISTRY/anagram-nginx:latest ./nginx
docker push $ECR_REGISTRY/anagram-nginx:latest

# 5. Apply the Rest of the Infrastructure
echo "▶ 5. Deploying Remaining Infrastructure (VPC, EC2, ALB)..."
cd terraform
terraform apply -auto-approve -var "code_hash=${CODE_HASH}"

echo "======================================"
echo " ✅ DEPLOYMENT SUCCESSFUL!"
echo " Waiting 3 minutes for EC2s to boot..."
echo "======================================"