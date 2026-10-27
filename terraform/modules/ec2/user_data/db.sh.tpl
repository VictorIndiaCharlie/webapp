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

# Patch password so DB and backend use the same value
sed -i "s|POSTGRES_PASSWORD: .*|POSTGRES_PASSWORD: ${postgres_password}|g" docker-compose.yml

docker compose up -d --no-deps db