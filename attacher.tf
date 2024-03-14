resource "aws_lambda_function" "instance_orchestrator_attacher_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "attacher-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Attacher"
  environment {
    variables = {
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
    }
  }
  function_name = "xosphere-instance-orchestrator-attacher"
  handler = "bootstrap"
  memory_size = var.attacher_memory_size
  role = aws_iam_role.instance_orchestrator_attacher_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.attacher_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_attacher_cloudwatch_log_group ]
}

resource "aws_iam_role" "instance_orchestrator_attacher_lambda_role" {
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
  name = "xosphere-instance-orchestrator-attacher-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_attacher_lambda_policy" {
  name = "xosphere-instance-orchestrator-attacher-policy"
  role = aws_iam_role.instance_orchestrator_attacher_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstanceStatus",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgs",
      "Effect": "Allow",
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {
          "autoscaling:ResourceTag/xosphere.io/instance-orchestrator/enabled": "true"
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgs",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": "*"
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
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "instance_orchestrator_attacher_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_attacher_lambda.arn
  principal = "lambda.amazonaws.com"
  source_arn = aws_lambda_function.xosphere_instance_orchestrator_lambda.arn
  statement_id = var.instance_orchestrator_attacher_lambda_permission_name_override == null ? "AllowExecutionFromLambda" : var.instance_orchestrator_attacher_lambda_permission_name_override
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_attacher_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-attacher"
  retention_in_days = var.attacher_lambda_log_retention
  tags = var.tags
}

resource "aws_iam_role" "xosphere_support_access_role" {
  count = (var.enable_auto_support > 0) ? 1 : 0

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "AWS": "arn:aws:iam::770759415832:root" },
      "Condition": {"StringEquals": {"sts:ExternalId": "${var.customer_id}"}},
      "Effect": "Allow",
      "Sid": "AllowXosphereSupportTrustPolicy"
    }
  ]
}
EOF
  managed_policy_arns = [ ]
  name = "xosphere-instance-orchestrator-auto-support-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "xosphere_support_access_policy" {
  count = var.enable_auto_support > 0 ? 1 : 0

  name = "xosphere-auto-support-policy"
  role = aws_iam_role.xosphere_support_access_role[0].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadOperationsOnXosphereLogGroups",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents",
        "logs:GetLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:*:*:log-group:/aws/lambda/xosphere-*",
        "arn:aws:logs:*:*:log-group:/aws/lambda/xosphere-*:log-stream:*"
      ]
    },
    {
      "Sid": "AllowReadOperationsOnXosphereManagedInstancesAndAsgs",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "autoscaling:Describe*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
