terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket       = "anagram-tfstate-412654396693"
    key          = "anagram-app/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
  }
}
