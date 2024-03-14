resource "aws_lambda_function" "instance_orchestrator_scheduler_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "scheduler-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Scheduler"
  environment {
    variables = {
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_schedule_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-scheduler"
  handler = "bootstrap"
  memory_size = var.io_scheduler_memory_size
  role = aws_iam_role.instance_orchestrator_scheduler_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_scheduler_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_scheduler_cloudwatch_event_log_group ]
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_scheduler_lambda_sqs_trigger" {
  event_source_arn = aws_sqs_queue.instance_orchestrator_schedule_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_scheduler_lambda.arn
  batch_size = 1
  enabled = true
  depends_on = [ aws_iam_role.instance_orchestrator_scheduler_lambda_role ]
}

resource "aws_lambda_permission" "instance_orchestrator_scheduler_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_scheduler_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_schedule_queue.arn
  statement_id = var.scheduler_lambda_permission_name_override == null ? "AllowSQSInvoke" : var.scheduler_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_scheduler_lambda_role" {
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
  name = "xosphere-instance-orchestrator-scheduler-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_scheduler_lambda_policy" {
  name = "xosphere-instance-orchestrator-scheduler-policy"
  role = aws_iam_role.instance_orchestrator_scheduler_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "elasticloadbalancing:DescribeInstanceHealth",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudwatchOperationsInXosphereNamespace",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"cloudwatch:namespace": ["xosphere.io/instance-orchestrator/*"]}
      }
    },
    {
      "Sid": "AllowEc2OperationsOnSchedules",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"aws:ResourceTag/xosphere.io/instance-orchestrator/schedule-name": ["*"]}
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

resource "aws_iam_role_policy" "instance_orchestrator_scheduler_lambda_policy_additional" {
  name = "xosphere-instance-orchestrator-scheduler-policy-additional"
  role = aws_iam_role.instance_orchestrator_scheduler_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLoadBalancingOperations",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets"
	  ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "instance_orchestrator_scheduler_lambda_policy_service_linked_roles" {
  name = "xosphere-instance-orchestrator-scheduler-policy-service-linked-roles"
  role = aws_iam_role.instance_orchestrator_scheduler_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
      "Sid": "AllowElasticLoadBalancingServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": ["elasticloadbalancing.amazonaws.com"]}}
    },
    {
      "Sid": "AllowElasticLoadBalancingServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_scheduler_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-scheduler"
  retention_in_days = var.io_scheduler_lambda_log_retention
  tags = var.tags
}

resource "aws_lambda_function" "instance_orchestrator_scheduler_cloudwatch_event_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "scheduler-cwe-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Scheduler On Cloudwatch Event"
  environment {
    variables = {
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_schedule_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-scheduler-cwe"
  handler = "bootstrap"
  memory_size = var.io_scheduler_memory_size
  role = aws_iam_role.instance_orchestrator_scheduler_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_scheduler_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_scheduler_cloudwatch_event_log_group ]
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_scheduler_cloudwatch_event_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-scheduler-cwe"
  retention_in_days = var.io_scheduler_lambda_log_retention
  tags = var.tags
}
