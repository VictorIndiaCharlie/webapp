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

# 1. BUILD BACKEND IMAGE
resource "docker_image" "backend" {
  name = "${module.ecr.registry_url}/anagram-backend:latest"
  build {
    context = "${path.module}/../backend"
  }
  keep_locally = true
  triggers = {
    always_run = timestamp()
  }
}
resource "docker_registry_image" "backend" {
  name = docker_image.backend.name
}

# 2. BUILD FRONTEND IMAGE
resource "docker_image" "frontend" {
  name = "${module.ecr.registry_url}/anagram-frontend:latest"
  build {
    context = "${path.module}/../frontend"
  }
  keep_locally = true
  triggers = {
    always_run = timestamp()
  }
}
resource "docker_registry_image" "frontend" {
  name = docker_image.frontend.name
}

# 3. BUILD NGINX IMAGE
resource "docker_image" "nginx" {
  name = "${module.ecr.registry_url}/anagram-nginx:latest"
  build {
    context = "${path.module}/../nginx"
  }
  keep_locally = true
  triggers = {
    always_run = timestamp()
  }
}
resource "docker_registry_image" "nginx" {
  name = docker_image.nginx.name
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

  depends_on = [
    docker_registry_image.backend,
    docker_registry_image.frontend,
    docker_registry_image.nginx
  ]
}

module "alb" {
  source               = "./modules/alb"
  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  alb_sg_id            = module.network.alb_sg_id
  frontend_instance_id = module.ec2.frontend_instance_id
}