resource "aws_s3_bucket" "instance_state_s3_bucket" {
  force_destroy = true
  bucket_prefix = var.state_bucket_name_override == null ? "xosphere-instance-orchestrator" : null
  bucket = var.state_bucket_name_override == null ? null : var.state_bucket_name_override
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = var.enhanced_security_use_cmk ? "aws:kms": "AES256"
        kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : null
      }
    }
  }

  dynamic "logging" {
    for_each = var.create_logging_buckets ? [1] : []
    content {
      target_bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
      target_prefix = "xosphere-instance-orchestrator-logs"
    }
  }
  tags = var.tags
}

resource "aws_s3_bucket_policy" "instance_state_s3_bucket_policy" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_bucket.arn}/*",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    },
    {
      "Sid": "RequireSecureTransport",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": [
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
      ],
      "Principal": "*",
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "instance_state_s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
