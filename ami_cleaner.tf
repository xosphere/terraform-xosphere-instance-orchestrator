resource "aws_lambda_function" "instance_orchestrator_ami_cleaner_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "ami-cleaner-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator AMI Cleaner"
  environment {
    variables = {
      REGIONS = local.regions
    }
  }
  function_name = "xosphere-instance-orchestrator-ami-cleaner"
  handler = "bootstrap"
  memory_size = var.ami_cleaner_memory_size
  role = aws_iam_role.instance_orchestrator_ami_cleaner_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.ami_cleaner_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_ami_cleaner_cloudwatch_log_group ]
}

resource "aws_lambda_permission" "instance_orchestrator_ami_cleaner_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_ami_cleaner_lambda.arn
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.instance_orchestrator_ami_cleaner_cloudwatch_event_rule.arn
  statement_id = var.ami_cleaner_lambda_permission_name_override == null ? "AllowExecutionFromCloudWatch" : var.ami_cleaner_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_ami_cleaner_role" {
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
  name = "xosphere-instance-orchestrator-ami-cleaner-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_ami_cleaner_policy" {
  name = "xosphere-instance-orchestrator-ami-cleaner-policy"
  role = aws_iam_role.instance_orchestrator_ami_cleaner_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:DescribeSnapshots",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeregisterImageOnEnabled",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2DeregisterImageXoGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
%{ else }
    {
      "Sid": "AllowEc2DeregisterImage",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*"
    },
%{ endif }
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeleteSnapshotXoGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": "arn:aws:ec2:*::snapshot/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
%{ else }
    {
      "Sid": "AllowEc2DeleteSnapshot",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": "arn:aws:ec2:*::snapshot/*"
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

resource "aws_cloudwatch_log_group" "instance_orchestrator_ami_cleaner_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-ami-cleaner"
  retention_in_days = var.ami_cleaner_lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_ami_cleaner_cloudwatch_event_rule" {
  name = "xosphere-ami-cleaner-schedule-event-rule"
  description = "Schedule for launching Xosphere Instance Orchestrator AMI Cleaner"
  schedule_expression = "cron(${var.ami_cleaner_cron_schedule})"
  is_enabled = true
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_ami_cleaner_cloudwatch_event_target" {
  arn = aws_lambda_function.instance_orchestrator_ami_cleaner_lambda.arn
  rule = aws_cloudwatch_event_rule.instance_orchestrator_ami_cleaner_cloudwatch_event_rule.name
  target_id = "xosphere-io-ami-cleaner-schedule"
}
