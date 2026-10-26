#!/bin/bash
set -e
dnf update -y
dnf install -y docker git
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone the repo (Replace with your actual Git repository URL)
git clone https://github.com/your-repo/anagram-generator.git /home/ec2-user/app
cd /home/ec2-user/app

# Ensure Nginx is exposed on port 80 (instead of 8080) for the ALB
sed -i 's/8080:80/80:80/g' docker-compose.yml

docker-compose up -d frontend nginx