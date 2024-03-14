//budget Driver

resource "aws_lambda_function" "instance_orchestrator_budget_driver_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "budget-driver-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Budget Driver"
  environment {
    variables = {
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_BUDGET_QUEUE = aws_sqs_queue.instance_orchestrator_budget_queue.id
      SQS_LAUNCHER_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_queue.id
      REGIONS = local.regions
      DAILY_BUFFER_SECONDS = var.daily_budget_grace_period_in_seconds
      MONTHLY_BUFFER_SECONDS = var.monthly_budget_grace_period_in_seconds
    }
  }
  function_name = "xosphere-instance-orchestrator-budget-driver"
  handler = "bootstrap"
  memory_size = var.io_budget_driver_memory_size
  role = aws_iam_role.instance_orchestrator_budget_driver_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_budget_driver_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_budget_driver_cloudwatch_log_group ]
}

resource "aws_lambda_permission" "instance_orchestrator_budget_driver_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_budget_driver_lambda.arn
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.instance_orchestrator_budget_driver_cloudwatch_event_rule.arn
  statement_id = var.budget_driver_lambda_permission_name_override == null ? "AllowExecutionFromCloudWatch" : var.budget_driver_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_budget_driver_lambda_role" {
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
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn ]
  name = "xosphere-instance-orchestrator-budget-driver-lambda-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_budget_driver_lambda_policy" {
  name = "xosphere-instance-orchestrator-budget-driver-lambda-policy"
  role = aws_iam_role.instance_orchestrator_budget_driver_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeTags",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "elasticloadbalancing:DescribeInstanceHealth",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth"
       ],
      "Resource": "*"
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2CreateTags",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": "*"
        }
      }
    },
%{ else }
    {
      "Sid": "AllowEc2CreateTags",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
%{ endif }
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgs",
      "Effect": "Allow",
      "Action": [
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"autoscaling:ResourceTag/xosphere.io/instance-orchestrator/budget-name": ["*"]}
      }
    },
    {
      "Sid": "AllowEc2OperationsOnBudgets",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"aws:ResourceTag/xosphere.io/instance-orchestrator/budget-name": ["*"]}
      }
    },
    {
      "Sid": "AllowPassRoleToEc2Instances",
      "Effect": "Allow",
      "Action": [
		"iam:PassRole"
	  ],
      "Resource": "${var.passrole_arn_resource_pattern}",
      "Condition": {
        "StringEquals": {"iam:PassedToService": "ec2.amazonaws.com"}
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

resource "aws_iam_role_policy" "instance_orchestrator_budget_driver_lambda_policy_service_linked_roles" {
  name = "xosphere-instance-orchestrator-budget-driver-lambda-policy-service-linked-roles"
  role = aws_iam_role.instance_orchestrator_budget_driver_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
      "Sid": "AllowEC2SpotServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": ["spot.amazonaws.com"]}}
    },
    {
      "Sid": "AllowEC2SpotServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/*"
    },
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
    },
	{
      "Sid": "AllowAutoScalingServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/autoscaling.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": ["autoscaling.amazonaws.com"]}}
    },
    {
      "Sid": "AllowAutoScalingServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/autoscaling.amazonaws.com/*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_budget_driver_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-budget-driver"
  retention_in_days = var.io_budget_driver_lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_budget_driver_cloudwatch_event_rule" {
  name = "xosphere-budget-driver-schedule-event-rule"
  description = "Schedule for launching Instance Orchestrator Budget Driver"
  schedule_expression = "cron(${var.budget_lambda_cron_schedule})"
  is_enabled = true
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_budget_driver_cloudwatch_event_target" {
  arn = aws_lambda_function.instance_orchestrator_budget_driver_lambda.arn
  rule = aws_cloudwatch_event_rule.instance_orchestrator_budget_driver_cloudwatch_event_rule.name
  target_id = "xosphere-instance-orchestrator-budget-schedule"
}
