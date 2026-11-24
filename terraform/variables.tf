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

variable "postgres_password" {
  description = "Postgres password used by all tiers"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "code_hash" {
  description = "SHA256 of backend+frontend+nginx source. Changing it replaces the app EC2 instances so they pull the fresh images."
  type        = string
  default     = "0"
}