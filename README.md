# Anagram Generator — Tier-3 Webapp on AWS

A full-stack anagram discovery tool that turns names into exact anagrams, sub-anagrams, and multi-word phrases. It also features a custom Markov-chain engine that generates pronounceable "invented" words.

The entire infrastructure, deployment pipeline, and serverless monitoring are fully automated using **Terraform**, **AWS ECR**, and **AWS Lambda**.

---

## Architecture

The application is split into three distinct tiers, sitting behind an Application Load Balancer (ALB), with an event-driven serverless monitoring stack.

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

### Serverless Monitoring Flow
```text
[ ALB: 5xx Errors ] ──> [ CloudWatch Alarm ] ──> [ SNS Topic ] ──> [ Lambda Function ]
                                                                         │
                                                             ┌───────────┴───────────┐
                                                             ▼                       ▼
                                                    [ CloudWatch Logs ]      [ Email Alert ]
```

---

## Tech Stack

- **Frontend:** Node.js + Express, Vanilla HTML/CSS/JS
- **Backend:** Python 3.11 + FastAPI, `psycopg2`
- **Database:** PostgreSQL 16 (Alpine)
- **Proxy:** Nginx (Alpine)
- **Infrastructure:** Terraform, AWS EC2, AWS ALB, AWS ECR, AWS S3
- **Monitoring:** AWS CloudWatch, Amazon SNS, AWS Lambda (Python 3.12)

---

## File Structure

```text
anagram-generator/
├── docker-compose.yml            # Local dev orchestration
├── README.md
├── .gitignore
│
├── .github/
│   └── workflows/
│       ├── deploy.yml            # Manual GitHub Actions deployment
│       └── destroy.yml           # Manual teardown workflow
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
        ├── alb/                  # Load Balancer & Target Group
        └── monitoring/           # CloudWatch Alarm, SNS, Lambda
```

---

## How the App Runs (Docker & ECR)

We use a **Build Once, Run Anywhere** architecture.

1. **Terraform builds locally:** During `terraform apply` (or GitHub Actions), a `null_resource` uses the host Docker daemon to build the `backend`, `frontend`, and `nginx` images.
2. **Push to ECR:** The images are immediately pushed to AWS Elastic Container Registry (ECR).
3. **EC2 Pulls the Images:** The EC2 instances no longer build code. When they boot, they authenticate to ECR and pull the pre-built images. This reduces boot time from ~8 minutes to ~45 seconds.

### The EC2 `user_data` Scripts
To ensure 100% reliability, the `user_data` scripts don't rely on extracting tarballs. They write the required configuration files (`docker-compose.yml` and `nginx.conf`) directly to disk, substituting the correct database IP and Backend IP before starting the containers.

---

## Terraform Configuration

The infrastructure is fully modularized. 

### 1. The Automated Build Flow
The root `main.tf` contains a `null_resource` that intercepts the deployment to build and push images before EC2s boot:
```hcl
resource "null_resource" "build_and_push" {
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = <<EOT
      # Build, push to ECR, and upload configs to S3
    EOT
  }
}
```

### 2. Serverless Monitoring Module
The `modules/monitoring` module provides an event-driven alerting system:
- **CloudWatch Alarm:** Watches the ALB for `HTTPCode_Target_5XX_Count > 5` over a 5-minute period.
- **SNS Topic:** Receives the alarm state change and fans it out.
- **Lambda Function (Python):** Triggered by SNS, it parses the alarm payload and logs it to CloudWatch. It is structured to easily be extended for auto-remediation (e.g., restarting a service via SSM).

### 3. IAM Least Privilege
The EC2 instances are governed by a single IAM role that attaches:
- `AmazonSSMManagedInstanceCore` (for secure, keyless terminal access)
- `AmazonEC2ContainerRegistryReadOnly` (to pull images)
- A custom inline policy allowing `s3:GetObject` on the specific artifact bucket.

---

## How to Deploy

### Prerequisites
- Terraform >= 1.10.0
- AWS CLI configured (`aws configure`)
- Docker running locally
- GitHub repository with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` secrets configured.

### One-Command Deployment (GitHub Actions)
Deployment is triggered manually via GitHub Actions.
1. Go to your repository -> **Actions** tab.
2. Select **Deploy to AWS** on the left.
3. Click **Run workflow**.
4. *Alternatively, run `terraform apply -auto-approve` locally from the `terraform/` directory.*

Terraform will:
1. Create the VPC, IAM roles, S3 bucket, ECR repositories, and monitoring resources.
2. Run local `docker build` and `docker push` commands.
3. Spin up the EC2 instances, which will pull the images and start the app.

### Accessing the App
Retrieve the ALB URL from Terraform outputs:
```bash
terraform output -raw alb_dns_name
```
Open that URL in your browser (ensure you use `http://`, not `https://`).

### Testing the Monitoring
You can manually trigger the CloudWatch Alarm to verify the Lambda function:
```bash
# Force the alarm into ALARM state
aws cloudwatch set-alarm-state \
  --alarm-name anagram-alb-5xx-errors \
  --state-value ALARM \
  --state-reason "Manual test of Lambda integration"

# View the Lambda logs
aws logs tail /aws/lambda/anagram-monitoring-handler --follow
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
*(Note: The local `docker-compose.yml` uses `build:` directives to compile the code locally, bypassing the need for AWS ECR credentials).*