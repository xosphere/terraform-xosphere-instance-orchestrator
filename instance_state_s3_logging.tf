resource "aws_s3_bucket" "instance_state_s3_logging_bucket" {
  count = var.create_logging_buckets ? 1 : 0
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = var.enhanced_security_use_cmk ? "aws:kms": "AES256"
        kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : null
      }
    }
  }
  force_destroy = true
  bucket_prefix = var.logging_bucket_name_override == null ? "xosphere-io-logging" : null
  bucket = var.logging_bucket_name_override == null ? null : var.logging_bucket_name_override
  tags = var.tags
}

resource "aws_s3_bucket_policy" "instance_state_s3_logging_bucket_policy" {
  count = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*",
      "Principal": {
        "Service": "logging.s3.amazonaws.com"
      },
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.instance_state_s3_bucket.arn}"
        },
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    },
    {
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    },
    {
      "Sid": "RequireSecureTransport",
      "Action": "s3:*",
      "Effect": "Deny",
      "Resource": [
        "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}",
        "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*"
      ],
      "Principal": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "instance_state_s3_logging_bucket_public_access_block" {
  count = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}