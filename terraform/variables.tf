variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "anagram"
}

variable "app_tarball_path" {
  description = "Local path to the app tarball produced by build.sh"
  type        = string
  default     = "/tmp/anagram-app.tar.gz"
}

variable "postgres_password" {
  description = "Postgres password used by all tiers"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}
