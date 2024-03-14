resource "aws_lambda_function" "instance_orchestrator_terraformer_lambda" {
  count = var.terraform_version != "" ? 1 : 0
  s3_bucket = local.s3_bucket
  s3_key = "terraformer-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Terraformer"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      TERRAFORM_VERSION = var.terraform_version != ""
      TERRAFORM_AWS_PROVIDER_VERSION = var.terraform_aws_provider_version
      TERRAFORM_BACKEND_AWS_REGION = var.terraform_backend_aws_region
      TERRAFORM_BACKEND_S3_BUCKET = var.terraform_backend_s3_bucket
      TERRAFORM_BACKEND_S3_KEY = var.terraform_backend_s3_key
      TERRAFORM_BACKEND_DYNAMODB_TABLE = var.terraform_backend_dynamodb_table
    }
  }
  function_name = "xosphere-instance-orchestrator-terraformer"
  handler = "bootstrap"
  memory_size = var.terraformer_memory_size
  role = aws_iam_role.instance_orchestrator_terraformer_lambda_role[0].arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.terraformer_lambda_timeout
  tags = var.tags
  ephemeral_storage {
    size = var.terraformer_ephemeral_storage
  }
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_terraformer_cloudwatch_log_group ]
}

resource "aws_iam_role" "instance_orchestrator_terraformer_lambda_role" {
  count = var.terraform_version != "" ? 1 : 0
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  name = "xosphere-instance-orchestrator-terraformer-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_terraformer_lambda_policy" {
  count = var.terraform_version != "" ? 1 : 0
  name = "xosphere-instance-orchestrator-terraformer-policy"
  role = aws_iam_role.instance_orchestrator_terraformer_lambda_role[0].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3OperationsOnXosphereObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::xosphere-*/*",
        "arn:aws:s3:::xosphere-*"
      ]
    },
%{ if var.enhanced_security_use_cmk }
    {
      "Sid": "AllowKmsCmk",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "${aws_kms_key.xosphere_kms_key[0].arn}"
    },
%{ endif }
%{ if local.needDefineTerraformS3Permission }
    {
      "Sid": "AllowS3BucketOperationsOnTerraformBackend",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${var.terraform_backend_s3_bucket}"
    },
    {
      "Sid": "AllowS3ObjectOperationsOnTerraformBackend",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${var.terraform_backend_s3_bucket}/*"
    },
%{ endif }
%{ if local.needDefineTerraformDynamoDBPermission }
    {
      "Sid": "AllowDynamoDBOperationOnTerraformBackend",
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/${var.terraform_backend_dynamodb_table}"
    },
%{ endif }
    {
      "Sid": "AllowLogOperationsOnXosphereLogGroups",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
	  ],
      "Resource": [
        "arn:aws:logs:*:*:log-group:/aws/lambda/xosphere-*",
        "arn:aws:logs:*:*:log-group:/aws/lambda/xosphere-*:log-stream:*"
      ]
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "instance_orchestrator_terraformer_lambda_permission" {
  count = var.terraform_version != "" ? 1 : 0
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_terraformer_lambda[0].arn
  principal = "lambda.amazonaws.com"
  source_arn = aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn
  statement_id = var.instance_orchestrator_terraformer_lambda_permission_name_override == null ? "AllowExecutionFromLambda" : var.instance_orchestrator_terraformer_lambda_permission_name_override
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_terraformer_cloudwatch_log_group" {
  count = var.terraform_version != "" ? 1 : 0
  name = "/aws/lambda/xosphere-instance-orchestrator-terraformer"
  retention_in_days = var.terraformer_lambda_log_retention
  tags = var.tags
}