data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.instance_profile_name

  user_data = templatefile("${path.module}/user_data/db.sh.tpl", {
    artifact_bucket   = var.artifact_bucket_name
    aws_region        = var.aws_region
    postgres_password = var.postgres_password          
    user_data_replace_on_change = true                
  })

                 

  tags = { Name = "${var.project_name}-db" }
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[1]
  vpc_security_group_ids = [var.backend_sg_id]
  iam_instance_profile   = var.instance_profile_name

  user_data = templatefile("${path.module}/user_data/backend.sh.tpl", {
    artifact_bucket    = var.artifact_bucket_name
    aws_region         = var.aws_region
    db_private_ip      = aws_instance.db.private_ip
    postgres_password  = var.postgres_password
    user_data_replace_on_change = true
  })

  depends_on = [aws_instance.db]
  tags       = { Name = "${var.project_name}-backend" }
}

resource "aws_instance" "frontend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.frontend_sg_id]
  iam_instance_profile   = var.instance_profile_name
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data/frontend.sh.tpl", {
    artifact_bucket   = var.artifact_bucket_name
    aws_region        = var.aws_region
    backend_private_ip = aws_instance.backend.private_ip
  })

  depends_on = [aws_instance.backend]
  tags       = { Name = "${var.project_name}-frontend" }
}