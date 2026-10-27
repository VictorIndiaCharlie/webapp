data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # so `terraform destroy` cleans up tarballs
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload the app tarball as part of `terraform apply`.
# The etag forces re-upload when the tarball changes.
resource "aws_s3_object" "app_tarball" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "anagram-app.tar.gz"
  source = var.app_tarball_path
  etag   = filemd5(var.app_tarball_path)
  content_type = "application/gzip"
}

# Least-privilege read policy attached to the shared EC2 role
resource "aws_iam_role_policy" "s3_read_artifacts" {
  name = "${var.project_name}-s3-read-artifacts"
  role = var.ec2_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["${aws_s3_bucket.artifacts.arn}/anagram-app.tar.gz"]
    }]
  })
}