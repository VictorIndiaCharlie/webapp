# Anagram Generator — Tier-3 Webapp on AWS

A full-stack anagram discovery tool that turns names into exact anagrams, sub-anagrams, and multi-word phrases. It also features a custom Markov-chain engine that generates pronounceable "invented" words.

The entire infrastructure and deployment pipeline is fully automated using **Terraform** and **AWS ECR**. 

---

## Architecture

The application is split into three distinct tiers, sitting behind an Application Load Balancer (ALB).

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
- **Backend:** Python 3.11 + FastAPI, `psycopg2`
- **Database:** PostgreSQL 16 (Alpine)
- **Proxy:** Nginx (Alpine)
- **Infrastructure:** Terraform, AWS EC2, AWS ALB, AWS ECR, AWS S3

---

## File Structure

```text
anagram-generator/
├── docker-compose.yml            # Local dev orchestration
├── README.md
├── .gitignore
│
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── app.py                    # FastAPI server + search logic
│   ├── inventor.py               # Markov chain pseudo-word generator
│   └── wordlist.txt              # Common English words
│
├── frontend/
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js                 # Express static server
│   └── public/                   # Dashboard UI (HTML/CSS/JS)
│
├── db/
│   └── init.sql                  # Schema + seeded names
│
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf                # Proxy configuration
│
└── terraform/
    ├── main.tf                   # Root config + Auto-build null_resource
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    └── modules/
        ├── network/              # VPC, Subnets, Security Groups
        ├── iam/                  # EC2 Roles, SSM, ECR Read-Only
        ├── artifact/             # S3 Bucket for configs
        ├── ecr/                  # ECR Repositories
        ├── ec2/                  # 3 Instances + user_data scripts
        └── alb/                  # Load Balancer & Target Group
```

---

## How the App Runs (Docker & ECR)

We use a **Build Once, Run Anywhere** architecture.

1. **Terraform builds locally:** During `terraform apply`, a `null_resource` uses your local Docker daemon to build the `backend`, `frontend`, and `nginx` images.
2. **Push to ECR:** The images are immediately pushed to AWS Elastic Container Registry (ECR).
3. **EC2 Pulls the Images:** The EC2 instances no longer build code. When they boot, they authenticate to ECR and pull the pre-built images. This reduces boot time from ~8 minutes to ~45 seconds.

### The `docker-compose.yml`
Because images are pre-built, the `docker-compose.yml` uses `image:` instead of `build:`. The `ECR_REGISTRY` variable is injected dynamically by Terraform at runtime.

```yaml
services:
  backend:
    image: ${ECR_REGISTRY}/anagram-backend:latest
    # ...
  frontend:
    image: ${ECR_REGISTRY}/anagram-frontend:latest
    # ...
  nginx:
    image: ${ECR_REGISTRY}/anagram-nginx:latest
    # ...
```

### The EC2 `user_data` Scripts
To ensure 100% reliability, the `user_data` scripts don't rely on extracting tarballs. They write the required configuration files (`docker-compose.yml` and `nginx.conf`) directly to disk, substituting the correct database IP and Backend IP before starting the containers.

---

## Terraform Configuration

The infrastructure is fully modularized. 

### The Automated Build Flow
To ensure you only ever have to run `terraform apply` (and never a manual shell script), the root `main.tf` contains a `null_resource` that intercepts the deployment:

```hcl
resource "null_resource" "build_and_push" {
  triggers = { always_run = timestamp() }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = <<EOT
      # 1. Create S3 tarball for configs
      tar -czf /tmp/anagram-app.tar.gz -C . .
      aws s3 cp /tmp/anagram-app.tar.gz s3://${module.artifact.bucket_name}/anagram-app.tar.gz
      
      # 2. Login to ECR
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.registry_url}
      
      # 3. Build & Push
      docker build -t ${module.ecr.registry_url}/anagram-backend:latest ./backend
      docker push ${module.ecr.registry_url}/anagram-backend:latest
      # (repeats for frontend and nginx)
    EOT
  }
}
```
*The EC2 module has a `depends_on = [null_resource.build_and_push]` to guarantee the instances don't launch until the images are in ECR.*

### The ECR Module
The new `modules/ecr` creates three private repositories and outputs the registry URL:
- `anagram-backend`
- `anagram-frontend`
- `anagram-nginx`

### IAM Least Privilege
The EC2 instances are governed by a single IAM role that attaches:
- `AmazonSSMManagedInstanceCore` (for secure, keyless terminal access)
- `AmazonEC2ContainerRegistryReadOnly` (to pull images)
- A custom inline policy allowing `s3:GetObject` on the specific artifact bucket.

---

## How to Deploy

### Prerequisites
- Terraform >= 1.7
- AWS CLI configured (`aws configure`)
- Docker running locally

### One-Command Deployment
You no longer need a `build.sh` script. Everything is handled by Terraform.

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Terraform will:
1. Create the VPC, IAM roles, S3 bucket, and ECR repositories.
2. Run local `docker build` and `docker push` commands.
3. Spin up the EC2 instances, which will pull the images and start the app.
4. Provision the ALB.

### Accessing the App
Retrieve the ALB URL:
```bash
terraform output -raw alb_dns_name
```
Open that URL in your browser (ensure you use `http://`, not `https://`).

### Instance Access
You do not need SSH keys. Access instances via AWS SSM:
```bash
aws ssm start-session --target <instance-id>
```

---

## Local Development

To run the stack locally for testing:

```bash
# Build and start everything
docker compose up --build -d

# The app will be available at http://localhost:8080
# Tear down
docker compose down -v
```
*(Note: Locally, `docker-compose.yml` automatically falls back to `build:` if `ECR_REGISTRY` is empty, allowing local testing without AWS).*