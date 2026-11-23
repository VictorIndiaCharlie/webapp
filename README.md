# Anagram Generator — Tier-3 Webapp on AWS

A full-stack anagram discovery tool that turns names into exact anagrams, sub-anagrams, and multi-word phrases. It features a custom Markov-chain engine that generates pronounceable "invented" words, fully deployed with Terraform, Docker, and AWS ECR.

---

## Architecture

The application uses a strict 3-tier architecture, sitting behind an Application Load Balancer (ALB), with an event-driven serverless monitoring stack and a fully automated CI/CD pipeline.

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
- **Backend:** Python 3.11 + FastAPI (2M+ word dictionary loaded in memory)
- **Database:** PostgreSQL 16 (Alpine)
- **Proxy:** Nginx (Alpine)
- **Infrastructure (CD):** Terraform, Docker Provider (Native ECR build), AWS EC2, ALB, ECR, S3
- **CI/CD:** GitHub Actions, `pytest`, `flake8`, `black` (Auto-formatter)
- **Monitoring:** AWS CloudWatch, Amazon SNS, AWS Lambda (Python 3.12)

---

## File Structure

```text
anagram-generator/
├── docker-compose.yml            # Local development orchestration
├── README.md
│
├── .github/workflows/
│   ├── ci.yml                    # PR Gatekeeper (Linting & Testing)
│   ├── deploy.yml                # Manual CD Pipeline (Terraform Apply)
│   └── destroy.yml               # Manual Teardown Pipeline
│
├── shell/
│   └── ci.sh                     # Local CI script (Black, Flake8, Pytest)
│
├── backend/                      # Python FastAPI Application
│   ├── Dockerfile
│   ├── app.py                    # FastAPI server & recursive search logic
│   ├── inventor.py               # Markov chain generator
│   ├── test_app.py               # Pytest unit tests
│   └── wordlist.txt              # 2M+ word dictionary
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
    ├── main.tf                   # Root config & Docker Image builds
    ├── providers.tf              # AWS, Time, and Docker Providers
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
# Note: The backend takes ~60 seconds to load the 2M word dictionary into memory.

# 3. Tear down
docker compose down -v
```

---

## 🧪 CI Pipeline (Continuous Integration)

The project implements a **Shift-Left** testing strategy. Code is validated locally before being pushed, and then validated again in the cloud as a PR Gatekeeper.

### 1. Local CI (`shell/ci.sh`)
Run `./shell/ci.sh` before committing. It uses an isolated Docker container to execute:
- **`black`:** Auto-formats the Python code to PEP-8 standards.
- **`flake8`:** Lints the code for syntax errors (ignoring cosmetic rules handled by Black).
- **Build Validation:** Runs `docker build` for the frontend and backend.
- **`pytest`:** Runs 4 unit tests validating the API endpoints and anagram logic.
- **`terraform fmt`:** Ensures the infrastructure code is properly formatted.

### 2. GitHub Actions CI (`.github/workflows/ci.yml`)
Triggered on every **Pull Request** to `main`. It spins up an Ubuntu runner, installs Terraform, and executes the exact same `shell/ci.sh` script. **Branch Protection Rules** prevent merging unless this pipeline passes.

---

## ☁️ CD Pipeline (AWS Deployment)

You can clone this repository and deploy the entire infrastructure into your own AWS account in minutes.

### Prerequisites
- Terraform installed
- AWS CLI configured (`aws configure`) with AdministratorAccess
- Docker running locally (Terraform uses it to build images)

### Quick Start (Local Terraform)
Because the state backend is dynamic (clone-and-run friendly), initialize it using your AWS Account ID:

```bash
# 1. Clone the repository
git clone https://github.com/VictorIndiaCharlie/webapp.git
cd webapp/terraform

# 2. Initialize and Deploy (Dynamically injects your state bucket)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
terraform init -reconfigure -backend-config="bucket=anagram-tfstate-${ACCOUNT_ID}"
terraform apply -auto-approve

# 3. Get the App URL
terraform output -raw alb_dns_name
```
*(Note: Ensure you use `http://` and not `https://` when opening the URL).*

### GitHub Actions CD (`.github/workflows/deploy.yml`)
Deployment is triggered manually via the GitHub UI.
1. Add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` to GitHub Secrets.
2. Go to **Actions** -> **Deploy to AWS** -> **Run workflow**.

---

## ⚙️ How it Works (The DevOps Pipeline)

1. **The Build Process (Pure Terraform):** When `terraform apply` runs, Terraform uses the **Kreuzwerker Docker Provider** to natively build the Docker images and push them to **AWS ECR** before provisioning the EC2s. There are no `null_resource` shell scripts required.
2. **The 3-Tier Setup:** 
   - Terraform spins up a **VPC** with public and private subnets.
   - Three `t3.micro` EC2 instances launch in private subnets.
   - The Backend EC2 `user_data` script creates a **2GB Swap File** to prevent Out-Of-Memory (OOM) crashes while loading the 2M word dictionary.
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
