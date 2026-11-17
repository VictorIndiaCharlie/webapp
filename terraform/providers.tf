terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Empty S3 backend. GitHub Actions will inject the account-specific bucket name.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}