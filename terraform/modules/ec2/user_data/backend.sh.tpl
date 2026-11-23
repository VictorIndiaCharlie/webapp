#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# 1. Create 2GB Swap File (CRITICAL FOR FREE TIER)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 2. Install ONLY Docker (No Git, No Buildx)
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 3. Create Config
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
      start_period: 300s
COMPOSE

# 4. Wait for DB
echo "Waiting for DB at ${db_private_ip}:5432..."
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${db_private_ip}/5432" 2>/dev/null; do
  sleep 3
done

# 5. Start Backend
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker compose up -d --no-deps backend