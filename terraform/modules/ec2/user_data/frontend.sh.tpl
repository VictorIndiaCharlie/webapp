#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf update -y
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install buildx (required by docker compose v5+)
curl -SL "https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

mkdir -p /home/ec2-user/app
aws s3 cp "s3://${artifact_bucket}/anagram-app.tar.gz" /tmp/app.tar.gz --region ${aws_region}
tar -xzf /tmp/app.tar.gz -C /home/ec2-user/app
cd /home/ec2-user/app

# Nginx listens on 80 (ALB forwards there)
sed -i 's/8080:80/80:80/g' docker-compose.yml

# Nginx proxies /api/ to the backend EC2 private IP
sed -i "s|http://backend:8000|http://${backend_private_ip}:8000|g" nginx/nginx.conf

docker compose up -d --no-deps frontend nginx