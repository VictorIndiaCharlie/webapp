output "alb_dns_name" {
  description = "Public DNS of the ALB"
  value       = module.alb.alb_dns_name
}

output "frontend_instance_id" {
  value = module.ec2.frontend_instance_id
}

output "backend_instance_id" {
  value = module.ec2.backend_instance_id
}

output "db_instance_id" {
  value = module.ec2.db_instance_id
}
