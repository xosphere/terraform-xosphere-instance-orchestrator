resource "aws_lambda_function" "instance_orchestrator_dlq_handler_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "dlq-handler-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Dead-Letter Queue Handler"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      DEAD_LETTER_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_dlq.id
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-dlq-handler"
  handler = "bootstrap"
  memory_size = var.dlq_handler_memory_size
  role = aws_iam_role.instance_orchestrator_dlq_handler_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.dlq_handler_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_dlq_handler_cloudwatch_log_group ]
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_dlq_handler_sqs_trigger" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_launcher_dlq.arn
  function_name = aws_lambda_function.instance_orchestrator_dlq_handler_lambda.arn
  depends_on = [ aws_iam_role.instance_orchestrator_dlq_handler_role ]
}

resource "aws_lambda_permission" "instance_orchestrator_dlq_handler_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_dlq_handler_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_launcher_dlq.arn
  statement_id = var.dlq_handler_lambda_permission_name_override == null ? "AllowSQSInvoke" : var.dlq_handler_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_dlq_handler_role" {
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
  name = "xosphere-instance-orchestrator-dql-handler-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_dlq_handler_policy" {
  name = "xosphere-instance-orchestrator-dlq-handler-policy"
  role = aws_iam_role.instance_orchestrator_dlq_handler_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEc2CreateTagsOnXogroups",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
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
      "Sid": "AllowS3OperationsOnXosphereObjects",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging"
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
      "Sid": "AllowSqsOperationsOnXosphereQueues",
      "Effect": "Allow",
      "Action": [
	    "sqs:ChangeMessageVisibility",
	    "sqs:DeleteMessage",
	    "sqs:GetQueueAttributes",
	    "sqs:ReceiveMessage",
	    "sqs:SendMessage"
      ],
      "Resource": "arn:aws:sqs:*:*:xosphere-*"
    },
    {
        "Sid": "AllowSecretManagerOperations",
        "Effect": "Allow",
        "Action": [
            "secretsmanager:GetSecretValue"
        ],
        "Resource": "${local.api_token_pattern}"
    },
    {
        "Sid": "AllowKmsOperations",
        "Effect": "Allow",
        "Action": [
            "kms:Decrypt"
        ],
        "Resource": "${local.kms_key_pattern}"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_dlq_handler_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-dlq-handler"
  retention_in_days = var.dlq_handler_lambda_log_retention
  tags = var.tags
}