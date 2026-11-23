#!/bin/bash
set -euo pipefail

# Auto-navigate to the project root
if [ -d "backend" ]; then
  :
elif [ -d "../backend" ]; then
  cd ..
else
  echo "❌ Cannot find backend/ directory. Please run from the project root or shell folder."
  exit 1
fi

echo "======================================"
echo " 🚀 STARTING LOCAL CI PIPELINE"
echo "======================================"

# 1. Code Linting & Auto-Formatting
echo -e "\n▶ 1. Code Formatting & Linting..."

echo "   - Building CI Docker image (to ensure tools are present)..."
docker build -q -t anagram-backend-ci ./backend > /dev/null

echo "   - Auto-formatting with black..."
# We mount the volume so black rewrites the files on your local machine
docker run --rm -v "$(pwd)/backend:/app" anagram-backend-ci black app.py inventor.py

echo "   - Linting Backend (flake8)..."
# Ignore E203 and W503 because black requires them to be ignored
docker run --rm -v "$(pwd)/backend:/app" anagram-backend-ci flake8 --max-line-length=88 --extend-ignore=E203,W503 app.py inventor.py

echo "   - Formatting Terraform..."
if command -v terraform &> /dev/null; then
    cd terraform
    terraform fmt -recursive 
    cd ..
    echo "   ✅ Terraform formatted."
else
    echo "   ⚠️ Terraform not installed locally, skipping fmt check."
fi

# 2. Build Validation
echo -e "\n▶ 2. Build Validation..."
echo "   - Building Backend Docker image..."
docker build -q -t anagram-backend-build ./backend > /dev/null
echo "   - Building Frontend Docker image..."
docker build -q -t anagram-frontend-build ./frontend > /dev/null
echo "   ✅ Docker images built successfully."

# 3. Unit Testing
echo -e "\n▶ 3. Unit Testing..."
echo "   - Running Backend Tests..."
docker run --rm -v "$(pwd)/backend:/app" anagram-backend-ci pytest test_app.py -v

echo -e "\n======================================"
echo " ✅ CI PIPELINE PASSED SUCCESSFULLY"
echo "======================================"