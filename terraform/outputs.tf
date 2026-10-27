output "alb_dns_name" {
  description = "Public URL of the anagram app"
  value       = "http://${module.alb.alb_dns_name}"
}

output "artifact_bucket" {
  value = module.artifact.bucket_name
}

output "instance_ids" {
  value = {
    frontend = module.ec2.frontend_instance_id
    backend  = module.ec2.backend_instance_id
    db       = module.ec2.db_instance_id
  }
}
