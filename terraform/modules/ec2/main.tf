data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "frontend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.frontend_sg_id]
  iam_instance_profile   = var.instance_profile_name
  user_data              = file("${path.module}/user_data/frontend.sh")
  tags                   = { Name = "${var.project_name}-frontend" }
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[1]
  vpc_security_group_ids = [var.backend_sg_id]
  iam_instance_profile   = var.instance_profile_name
  user_data              = file("${path.module}/user_data/backend.sh")
  tags                   = { Name = "${var.project_name}-backend" }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.instance_profile_name
  user_data              = file("${path.module}/user_data/db.sh")
  tags                   = { Name = "${var.project_name}-db" }
}