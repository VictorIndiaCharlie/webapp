#!/bin/bash
set -e # Exit immediately if any command fails

# Auto-navigate to the project root
if [ -d "backend" ]; then
  : # already in root
elif [ -d "../backend" ]; then
  cd ..
else
  echo "❌ Cannot find backend/ directory. Please run from the project root or shell folder."
  exit 1
fi

echo "======================================"
echo " 🚀 STARTING LOCAL CI PIPELINE"
echo "======================================"

# 1. Code Linting
echo -e "\n▶ 1. Code Linting..."
echo "   - Linting Backend (flake8)..."
docker build -q -t anagram-backend-ci ./backend > /dev/null
docker run --rm anagram-backend-ci flake8 --ignore=E231,E501,E302 app.py

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
# NEW: Added -v "$(pwd)/backend:/app" to mount the test file into the container
docker run --rm -v "$(pwd)/backend:/app" anagram-backend-ci pytest test_app.py -v

echo -e "\n======================================"
echo " ✅ CI PIPELINE PASSED SUCCESSFULLY"
echo "======================================"