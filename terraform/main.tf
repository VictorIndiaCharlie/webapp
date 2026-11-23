module "network" {
  source       = "./modules/network"
  project_name = var.project_name
  aws_region   = var.aws_region
}

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

module "artifact" {
  source       = "./modules/artifact"
  project_name = var.project_name
  ec2_role_id  = module.iam.ec2_role_id
}

module "ecr" {
  source     = "./modules/ecr"
  aws_region = var.aws_region
}


resource "null_resource" "build_and_push" {

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = <<EOT
      echo "▶ 1. Creating app tarball..."
      tar --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc' --exclude='.venv' --exclude='terraform' --exclude='.terraform' --exclude='terraform.tfstate*' --exclude='shell' -czf /tmp/anagram-app.tar.gz -C . .

      echo "▶ 2. Uploading tarball to S3..."
      aws s3 cp /tmp/anagram-app.tar.gz s3://${module.artifact.bucket_name}/anagram-app.tar.gz --region ${var.aws_region}

      echo "▶ 3. Logging into ECR..."
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.registry_url}

      echo "▶ 4. Building images locally..."
      docker build -t ${module.ecr.registry_url}/anagram-backend:latest ./backend
      docker build -t ${module.ecr.registry_url}/anagram-frontend:latest ./frontend
      docker build -t ${module.ecr.registry_url}/anagram-nginx:latest ./nginx

      echo "▶ 5. Pushing images to ECR..."
      docker push ${module.ecr.registry_url}/anagram-backend:latest
      docker push ${module.ecr.registry_url}/anagram-frontend:latest
      docker push ${module.ecr.registry_url}/anagram-nginx:latest
    EOT
  }

  depends_on = [module.artifact, module.ecr]
}



module "ec2" {
  source                = "./modules/ec2"
  project_name          = var.project_name
  aws_region            = var.aws_region
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  frontend_sg_id        = module.network.frontend_sg_id
  backend_sg_id         = module.network.backend_sg_id
  db_sg_id              = module.network.db_sg_id
  instance_profile_name = module.iam.instance_profile_name
  artifact_bucket_name  = module.artifact.bucket_name
  postgres_password     = var.postgres_password
  ecr_registry          = module.ecr.registry_url

<<<<<<< HEAD
  depends_on = [time_sleep.wait_for_db]
=======

>>>>>>> 80fc54ada2628394a7d33169622f6a4e33ca0d74
  depends_on = [null_resource.build_and_push]
}

module "alb" {
  source               = "./modules/alb"
  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  alb_sg_id            = module.network.alb_sg_id
  frontend_instance_id = module.ec2.frontend_instance_id
}

module "monitoring" {
  source         = "./modules/monitoring"
  project_name   = var.project_name
  alb_arn_suffix = module.alb.alb_arn_suffix # This output must be added
  alert_email    = "your-email@example.com"  # Optional
}