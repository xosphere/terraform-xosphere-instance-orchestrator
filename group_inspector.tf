resource "aws_lambda_function" "instance_orchestrator_group_inspector_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "snapshot-creator-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Group Inspector"
  environment {
    variables = {
      REGIONS = local.regions
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      GROUP_INSPECTOR_QUEUE_URL = aws_sqs_queue.instance_orchestrator_group_inspector_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-group-inspector"
  handler = "bootstrap"
  memory_size = var.io_group_inspector_memory_size
  role = aws_iam_role.instance_orchestrator_group_inspector_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_group_inspector_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_group_inspector_cloudwatch_log_group ]
}

resource "aws_lambda_permission" "instance_orchestrator_group_inspector_schedule_cloudwatch_event_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_group_inspector_lambda.arn
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.instance_orchestrator_group_inspector_schedule_cloudwatch_event_rule.arn
  statement_id = var.group_inspector_schedule_cloudwatch_event_lambda_permission_name_override == null ? "AllowGroupInspectorExecutionFromCloudWatchSchedule" : var.group_inspector_schedule_cloudwatch_event_lambda_permission_name_override
}

resource "aws_lambda_permission" "instance_orchestrator_group_inspector_sqs_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_group_inspector_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_group_inspector_queue.arn
  statement_id = var.group_inspector_sqs_lambda_permission_name_override == null ? "AllowGroupInspectorExecutionFromSqs" : var.group_inspector_sqs_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_group_inspector_role" {
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
  name = "xosphere-instance-orchestrator-group-inspector-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_group_inspector_policy" {
  name = "xosphere-instance-orchestrator-group-inspector-policy"
  role = aws_iam_role.instance_orchestrator_group_inspector_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeTags"
       ],
      "Resource": "*"
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
    },
    {
        "Sid": "AllowSqsConsumeOnGroupInspectorQueue",
        "Effect": "Allow",
        "Action": [
            "sqs:ChangeMessageVisibility",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:ReceiveMessage",
            "sqs:SendMessage"
        ],
        "Resource": "${aws_sqs_queue.instance_orchestrator_group_inspector_queue.arn}"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_group_inspector_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-group-inspector"
  retention_in_days = var.io_group_inspector_lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_group_inspector_schedule_cloudwatch_event_rule" {
  name = "xosphere-group-inspector-schedule-event-rule"
  description = "Schedule for launching Xosphere Instance Orchestrator Group Inspector"
  schedule_expression = "cron(${var.group_inspector_cron_schedule})"
  is_enabled = true
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "xosphere_instance_orchestrator_group_inspector_schedule_cloudwatch_event_target" {
  arn = aws_lambda_function.instance_orchestrator_group_inspector_lambda.arn
  rule = aws_cloudwatch_event_rule.instance_orchestrator_group_inspector_schedule_cloudwatch_event_rule.name
  target_id = "xosphere-io-group-inspector-schedule"
}