#!/usr/bin/env bash
set -euo pipefail

# Auto-navigate to the project root
if [ -d "backend" ]; then
  : # already in root
elif [ -d "../backend" ]; then
  cd ..
else
  echo "❌ Cannot find backend/ directory. Please run from the project root or shell folder."
  exit 1
fi

AWS_REGION="eu-central-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "▶ 1. Creating app tarball for the EC2s..."
OUT="/tmp/anagram-app.tar.gz"
rm -f "$OUT"
tar \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='.venv' \
  --exclude='terraform' \
  --exclude='.terraform' \
  --exclude='terraform.tfstate*' \
  --exclude='shell' \
  -czf "$OUT" \
  -C . .

echo "▶ 2. Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

echo "▶ 3. Building images locally..."
docker build -t anagram-backend ./backend
docker build -t anagram-frontend ./frontend
docker build -t anagram-nginx ./nginx

echo "▶ 4. Tagging images for ECR..."
docker tag anagram-backend $ECR_REGISTRY/anagram-backend:latest
docker tag anagram-frontend $ECR_REGISTRY/anagram-frontend:latest
docker tag anagram-nginx $ECR_REGISTRY/anagram-nginx:latest

echo "▶ 5. Pushing to ECR..."
docker push $ECR_REGISTRY/anagram-backend:latest
docker push $ECR_REGISTRY/anagram-frontend:latest
docker push $ECR_REGISTRY/anagram-nginx:latest

echo "✓ Build and Push complete!"