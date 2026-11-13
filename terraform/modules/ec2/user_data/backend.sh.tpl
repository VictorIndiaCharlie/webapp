#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# 1. Install Docker and Buildx
dnf update -y
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

curl -SL "https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# 2. Create configs directly (Quoted heredoc)
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

cat << 'COMPOSE' > docker-compose.yml
services:
  backend:
    image: ${ecr_registry}/anagram-backend:latest
    container_name: anagram_backend
    ports:
      - "8000:8000"
    restart: unless-stopped
    environment:
      POSTGRES_HOST: ${db_private_ip}
      POSTGRES_PORT: 5432
      POSTGRES_DB: anagrams
      POSTGRES_USER: anagram
      POSTGRES_PASSWORD: ${postgres_password}
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request,sys; urllib.request.urlopen('http://localhost:8000/health')\" || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
COMPOSE

# 3. Log into ECR and Start Backend
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker compose up -d --no-deps backend