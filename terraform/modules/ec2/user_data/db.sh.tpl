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

mkdir -p /home/ec2-user/app
cd /home/ec2-user/app
cat << 'COMPOSE' > docker-compose.yml
services:
  db:
    image: postgres:16-alpine
    container_name: anagram_db
    ports:
      - "5432:5432"
    restart: unless-stopped
    environment:
      POSTGRES_DB: anagrams
      POSTGRES_USER: anagram
      POSTGRES_PASSWORD: ${postgres_password}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U anagram -d anagrams"]
      interval: 5s
      timeout: 5s
      retries: 10
COMPOSE

docker compose up -d --no-deps db