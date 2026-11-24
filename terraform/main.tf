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
  code_hash             = var.code_hash

  # Instances only boot AFTER docker build+push completes (deploy script order),
  # but we also wait for the ECR repos to exist so a fresh apply can't race.
  depends_on = [module.ecr]
}

module "alb" {
  source               = "./modules/alb"
  project_name         = var.project_name
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  alb_sg_id            = module.network.alb_sg_id
  frontend_instance_id = module.ec2.frontend_instance_id
}