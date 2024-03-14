resource "aws_lambda_function" "instance_orchestrator_xogroup_enabler_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "xogroup-enabler-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Xogroup Enabler"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
    }
  }
  function_name = "xosphere-instance-orchestrator-xogroup-enabler"
  handler = "bootstrap"
  memory_size = var.io_xogroup_enabler_memory_size
  role = aws_iam_role.instance_orchestrator_xogroup_enabler_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_xogroup_enabler_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_xogroup_enabler_cloudwatch_event_log_group ]
}

resource "aws_iam_role" "instance_orchestrator_xogroup_enabler_lambda_role" {
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
  managed_policy_arns = [ ]
  name = "xosphere-instance-orchestrator-xogroup-enabler-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_xogroup_enabler_lambda_policy" {
  name = "xosphere-instance-orchestrator-xogroup-enabler-policy"
  role = aws_iam_role.instance_orchestrator_xogroup_enabler_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": [ "*" ]
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags"
      ],
      "Resource": [ "*" ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowS3OperationsOnXosphereObjects",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket",
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
    {
      "Sid": "AllowCloudwatchOperationsInXosphereNamespace",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "cloudwatch:namespace": [
            "xosphere.io/instance-orchestrator/*"
          ]
        }
      }
    },
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
    },
    {
      "Sid": "AllowSqsConsumeOnXogroupEnablerQueue",
      "Effect": "Allow",
      "Action": [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Resource": [
        "${aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.arn}"
      ]
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_xogroup_enabler_cloudwatch_event_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-xogroup-enabler"
  retention_in_days = var.io_xogroup_enabler_lambda_log_retention
  tags = var.tags
}
