# Anagram Generator — Tier-3 Webapp on AWS

A full-stack anagram discovery tool that turns names into exact anagrams, sub-anagrams, and multi-word phrases. It features a custom Markov-chain engine that generates pronounceable "invented" words, fully deployed with Terraform, Docker, and AWS ECR.

---

## Architecture

The application uses a strict 3-tier architecture, sitting behind an Application Load Balancer (ALB), with a fully automated CI/CD pipeline.

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
- **Database:** PostgreSQL 16 (Alpine), seeded on first boot
- **Proxy:** Nginx (Alpine)
- **Infrastructure (CD):** Terraform, Docker (ECR), AWS EC2, ALB, ECR, S3
- **CI/CD:** GitHub Actions, `pytest`, `flake8`, `black` (Auto-formatter)

---

## File Structure

```text
anagram-generator/
├── docker-compose.yml            # Local development orchestration
├── deploy.sh                     # One-command AWS deploy (local)
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
│   ├── wordlist.txt              # 2M+ word dictionary
│   └── db/init.sql               # DB schema & seed data (same as root db/)
│
├── frontend/                     # Node.js UI
│   ├── Dockerfile
│   └── public/                   # HTML/CSS/JS Dashboard
│
├── db/
│   └── init.sql                  # Database schema & seed data (local dev + EC2 DB)
│
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf                # Proxy configuration
│
└── terraform/                    # AWS Infrastructure
    ├── main.tf                   # Root config & module wiring (code_hash redeploy)
    ├── providers.tf              # AWS Provider + S3 state backend
    └── modules/
        ├── network/              # VPC, Subnets, Security Groups
        ├── iam/                  # EC2 Roles & Permissions
        ├── ecr/                  # Container Registries
        ├── artifact/             # S3 Artifact Bucket
        ├── ec2/                  # 3 Instances + user_data scripts
        └── alb/                  # Load Balancer
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
# Note: The DB seeds itself from db/init.sql on first boot, so the
# dictionary (and names you add) work out of the box.

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
- Docker running locally (the deploy script builds the images and pushes them to ECR)

### Quick Start (One Command)
Because the state backend is dynamic (clone-and-run friendly), a single script handles the whole deploy — it creates your state bucket, pre-provisions the ECR repositories + S3 bucket, builds and pushes the images to ECR, then runs the full `terraform apply`:

```bash
# 1. Clone the repository
git clone https://github.com/VictorIndiaCharlie/webapp.git
cd webapp

# 2. Deploy everything
./deploy.sh

# 3. Get the App URL (run from the terraform/ folder)
terraform output -raw alb_dns_name
```
*(Note: Ensure you use `http://` and not `https://` when opening the URL).*

### Manual Steps (what `deploy.sh` does under the hood)
```bash
# 1. Compute your account ID and the code hash
export AWS_REGION="eu-central-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
STATE_BUCKET="anagram-tfstate-${ACCOUNT_ID}"
CODE_HASH=$(find backend frontend nginx -type f -not -path '*/node_modules/*' \
  | sort | xargs sha256sum | sha256sum | awk '{print $1}')

# 2. Ensure the state bucket exists, then init
aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || \
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION
cd terraform
terraform init -reconfigure -backend-config="bucket=$STATE_BUCKET"

# 3. Provision ECR repositories + artifact bucket FIRST (so pushes have a home)
terraform apply -auto-approve -target=module.ecr -target=module.artifact
cd ..

# 4. Login to ECR & build/push the 3 images
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker build -t $ECR_REGISTRY/anagram-backend:latest ./backend && docker push $ECR_REGISTRY/anagram-backend:latest
docker build -t $ECR_REGISTRY/anagram-frontend:latest ./frontend && docker push $ECR_REGISTRY/anagram-frontend:latest
docker build -t $ECR_REGISTRY/anagram-nginx:latest ./nginx && docker push $ECR_REGISTRY/anagram-nginx:latest

# 5. Full deploy (code_hash replaces the app EC2s only when code changed)
cd terraform
terraform apply -auto-approve -var "code_hash=${CODE_HASH}"
```

### GitHub Actions CD (`.github/workflows/deploy.yml`)
Deployment is triggered manually via the GitHub UI.
1. Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to GitHub Secrets (the region `eu-central-1` is built into the workflow).
2. Go to **Actions** -> **Deploy to AWS** -> **Run workflow**.

---

## ⚙️ How it Works (The DevOps Pipeline)

1. **The Build Process:** The deploy script (local `./deploy.sh` or the GitHub Actions workflow) logs into **AWS ECR**, builds the three Docker images, and pushes them to your registry. Terraform pre-applies the ECR + S3 modules so the repos and bucket exist before the pushes, then provisions the EC2s. Every deploy computes a **CODE_HASH** over the `backend/`, `frontend/`, and `nginx/` sources — when it changes, only the Backend and Frontend instances are replaced (they pull the fresh images on boot), while the DB instance is left untouched so your data survives redeploys.
2. **The 3-Tier Setup:** 
   - Terraform spins up a **VPC** with public and private subnets.
   - Three `t3.micro` EC2 instances launch in private subnets.
   - The Backend EC2 `user_data` script creates a **2GB Swap File** to prevent Out-Of-Memory (OOM) crashes while loading the 2M word dictionary.
   - Startup order is enforced in the `user_data` scripts: the DB boots first, the Backend waits for the DB port, and the Frontend waits for the Backend port.
3. **The Request Flow:** 
   - User hits the **ALB**.
   - ALB forwards to the **Frontend EC2** (Nginx).
   - Nginx serves static files and proxies `/api` requests to the **Backend EC2** (FastAPI).
   - FastAPI queries the **DB EC2** (PostgreSQL) and returns the results.
