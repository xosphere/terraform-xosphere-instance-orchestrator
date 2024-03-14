resource "aws_kms_key" "xosphere_kms_key" {
  count = var.enhanced_security_use_cmk ? 1 : 0
  description             = "Xosphere KSM CMK key"
  enable_key_rotation = true
  deletion_window_in_days = 20
  policy = jsonencode({
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = join("", ["arn:aws:iam::", data.aws_caller_identity.current.account_id, ":root"])
        }
        Resource = "*" # '*' here means "this kms key" https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
        Sid      = "Delegate permission to root user"
      },
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Resource = "*" # '*' here means "this kms key" https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
        Sid      = "S3 Access logging"
      }
    ]
    Version = "2012-10-17"
  })
}

resource "aws_kms_alias" "xosphere_kms_key_alias" {
  count = var.enhanced_security_use_cmk ? 1 : 0
  name          = "alias/XosphereKmsKey"
  target_key_id = aws_kms_key.xosphere_kms_key[0].key_id
}