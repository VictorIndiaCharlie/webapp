#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

mkdir -p /home/ec2-user/app/nginx
cd /home/ec2-user/app

cat << 'COMPOSE' > docker-compose.yml
services:
  frontend:
    image: ${ecr_registry}/anagram-frontend:latest
    container_name: anagram_frontend
    restart: unless-stopped
    environment:
      PORT: 3000
      # Points at the dedicated backend EC2 (this instance does not host
      # the backend container — that leftover service was removed).
      BACKEND_URL: http://${backend_private_ip}:8000
# Changing this line replaces the instance (user_data_replace_on_change)
# so a new code hash always pulls the fresh image on a clean boot.
# code_hash: ${code_hash}

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

echo "Waiting for Backend at ${backend_private_ip}:8000..."
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${backend_private_ip}/8000" 2>/dev/null; do
  sleep 3
done

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker compose up -d --no-deps frontend nginx