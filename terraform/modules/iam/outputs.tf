output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_role_id" {
  value = aws_iam_role.ec2_role.id
}