variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "frontend_sg_id" { type = string }
variable "backend_sg_id" { type = string }
variable "db_sg_id" { type = string }
variable "instance_profile_name" { type = string }