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

# 2. Create configs directly
mkdir -p /home/ec2-user/app/nginx
cd /home/ec2-user/app

cat << 'COMPOSE' > docker-compose.yml
services:
  backend:
    image: ${ecr_registry}/anagram-backend:latest
    container_name: anagram_backend
    ports:
      - "8000:8000"
    restart: unless-stopped

  frontend:
    image: ${ecr_registry}/anagram-frontend:latest
    container_name: anagram_frontend
    restart: unless-stopped
    environment:
      PORT: 3000
      BACKEND_URL: http://backend:8000

  nginx:
    image: ${ecr_registry}/anagram-nginx:latest
    container_name: anagram_nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - frontend
      - backend
COMPOSE

cat << 'NGINX' > nginx/nginx.conf
resolver 127.0.0.11 valid=10s ipv6=off;
server {
    listen 80;
    server_name localhost;
    set $backend_upstream  http://${backend_private_ip}:8000;
    set $frontend_upstream http://frontend:3000;
    location /api/ {
        proxy_pass $backend_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    location / {
        proxy_pass $frontend_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

# 3. Log into ECR and Start Containers
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker compose up -d --no-deps frontend nginx