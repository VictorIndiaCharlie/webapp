data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "backend" {
  name                 = "anagram-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "frontend" {
  name                 = "anagram-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "nginx" {
  name                 = "anagram-nginx"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}