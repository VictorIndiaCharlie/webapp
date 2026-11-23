terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # ADD THIS BLOCK
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
  
  backend "s3" {
    key    = "anagram-app/terraform.tfstate"
    region = "eu-central-1"
  }
}

provider "aws" {
  region = var.aws_region
}