# Anagram Generator — Tier-3 Webapp on AWS

A full-stack anagram discovery tool that turns names into exact anagrams, sub-anagrams, and multi-word phrases. It features a custom Markov-chain engine that generates pronounceable "invented" words, fully deployed with Terraform, Docker, and AWS ECR.

---

## Architecture

The application uses a strict 3-tier architecture, sitting behind an Application Load Balancer (ALB), with an event-driven serverless monitoring stack.

```text
                          Internet
                             │
                             ▼
              ┌──────────────────────────────┐
              │        ALB (public)          │  ← Port 80 (HTTP)
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Frontend EC2 (private)     │
              │  ┌─────────┐  ┌──────────┐   │
              │  │  Nginx  │→ │  Node.js │   │  ← Proxies /api to backend
              │  └────┬────┘  └──────────┘   │
              └───────┼──────────────────────┘
                      │ 
                      ▼
              ┌──────────────────────────────┐
              │   Backend EC2 (private)      │
              │  ┌──────────────────────┐    │
              │  │  Python FastAPI      │    │  ← Handles anagram logic
              │  └──────────┬───────────┘    │
              └─────────────┼────────────────┘
                            │ 
                            ▼
              ┌──────────────────────────────┐
              │     DB EC2 (private)         │
              │  ┌──────────────────────┐    │
              │  │  PostgreSQL 16       │    │
              │  └──────────────────────┘    │
              └──────────────────────────────┘
```

---

## Tech Stack

- **Frontend:** Node.js + Express, Vanilla HTML/CSS/JS
- **Backend:** Python 3.11 + FastAPI
- **Database:** PostgreSQL 16 (Alpine)
- **Proxy:** Nginx (Alpine)
- **Infrastructure:** Terraform, AWS EC2, AWS ALB, AWS ECR, AWS S3
- **Monitoring:** AWS CloudWatch, Amazon SNS, AWS Lambda (Python 3.12)

---

## File Structure

```text
anagram-generator/
├── docker-compose.yml            # Local development orchestration
├── README.md
│
├── backend/                      # Python FastAPI Application
│   ├── Dockerfile
│   ├── app.py                    # Search logic
│   └── inventor.py               # Markov chain generator
│
├── frontend/                     # Node.js UI
│   ├── Dockerfile
│   └── public/                   # HTML/CSS/JS Dashboard
│
├── db/
│   └── init.sql                  # Database schema & seed data
│
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf                # Proxy configuration
│
└── terraform/                    # AWS Infrastructure
    ├── main.tf                   # Root config + Automated Docker build
    ├── providers.tf
    └── modules/
        ├── network/              # VPC, Subnets, Security Groups
        ├── iam/                  # EC2 Roles & Permissions
        ├── ecr/                  # Container Registries
        ├── ec2/                  # 3 Instances + user_data scripts
        ├── alb/                  # Load Balancer
        └── monitoring/           # Lambda, SNS, CloudWatch
```

---

## 🚀 How to Deploy Locally

You only need Docker and Docker Compose installed.

```bash
# 1. Build and start the containers
docker compose up --build -d

# 2. Access the app
# Open http://localhost:8080 in your browser

# 3. Tear down
docker compose down -v
```

---

## ☁️ How to Deploy in AWS (Quick Start)

You can clone this repository and deploy the entire infrastructure into your own AWS account in minutes.

**Prerequisites:**
- Terraform installed
- AWS CLI configured (`aws configure`) with AdministratorAccess
- Docker running locally

```bash
# 1. Clone the repository
git clone https://github.com/VictorIndiaCharlie/webapp.git
cd webapp/terraform

# 2. Initialize and Deploy
terraform init
terraform apply -auto-approve

# 3. Get the App URL
terraform output -raw alb_dns_name
```
*(Note: Ensure you use `http://` and not `https://` when opening the URL).*

---

## ⚙️ How it Works (The DevOps Pipeline)

1. **The Build Process:** When `terraform apply` runs, a `null_resource` executes `docker build` on your local machine for the backend, frontend, and Nginx. It then pushes these images to **AWS ECR** (Elastic Container Registry).
2. **The 3-Tier Setup:** 
   - Terraform spins up a **VPC** with public and private subnets.
   - Three EC2 instances launch in private subnets.
   - The instances run `user_data` scripts that authenticate to ECR, pull the pre-built images, and start the containers via Docker Compose.
3. **The Request Flow:** 
   - User hits the **ALB**.
   - ALB forwards to the **Frontend EC2** (Nginx).
   - Nginx serves static files and proxies `/api` requests to the **Backend EC2** (FastAPI).
   - FastAPI queries the **DB EC2** (PostgreSQL) and returns the results.

---

## 🚨 Serverless Monitoring (Lambda)

Instead of managing a heavy Prometheus/Grafana stack, this repo uses AWS-native serverless monitoring.

**The Flow:**
1. **CloudWatch Alarm:** Watches the ALB for `HTTPCode_Target_5XX_Count`. If there are more than 5 server errors in 5 minutes, it triggers.
2. **Amazon SNS:** The alarm publishes a message to an SNS Topic.
3. **AWS Lambda:** A Python Lambda function is subscribed to the topic. When triggered, it parses the alarm payload and logs the details to CloudWatch.
