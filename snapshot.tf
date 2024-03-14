resource "aws_lambda_function" "instance_orchestrator_snapshot_creator_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "snapshot-creator-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Snapshot Creator"
  environment {
    variables = {
      REGIONS = local.regions
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_SNAPSHOT_QUEUE: aws_sqs_queue.instance_orchestrator_snapshot_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-snapshot-creator"
  handler = "bootstrap"
  memory_size = var.snapshot_creator_memory_size
  role = aws_iam_role.instance_orchestrator_snapshot_creator_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.snapshot_creator_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_snapshot_creator_cloudwatch_log_group ]
}

resource "aws_lambda_permission" "instance_orchestrator_snapshot_creator_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.instance_orchestrator_snapshot_creator_cloudwatch_event_rule.arn
  statement_id = var.snapshot_creator_lambda_permission_name_override == null ? "AllowExecutionFromCloudWatch" : var.snapshot_creator_lambda_permission_name_override
}

resource "aws_lambda_permission" "instance_orchestrator_snapshot_creator_sqs_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_snapshot_queue.arn
  statement_id = var.snapshot_creator_sqs_lambda_permission_name_override == null ? "AllowSQSInvoke" : var.snapshot_creator_sqs_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_snapshot_creator_role" {
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
  name = "xosphere-instance-orchestrator-snapshot-creator-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_snapshot_creator_policy" {
  name = "xosphere-instance-orchestrator-snapshot-creator-policy"
  role = aws_iam_role.instance_orchestrator_snapshot_creator_role.id
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
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes"
       ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEc2CreateSnapshotVolume",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
	  ],
      "Resource": [
        "arn:aws:ec2:*:*:volume/*"
      ]
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshot",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
	  ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshots",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "ec2:CreateAction": "CreateSnapshot",
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeleteSnapshotXoGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
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
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ]
    },
%{ endif }
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2CreateTags",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*",
        "arn:aws:ec2:*:*:volume/*"
      ],
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
      "Resource": [
        "arn:aws:ec2:*::snapshot/*",
        "arn:aws:ec2:*:*:volume/*"
      ]
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
    },
	  {
      "Sid": "AllowSqsOperationsOnXosphereQueues",
      "Effect": "Allow",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage"
      ],
      "Resource": "arn:aws:sqs:*:*:xosphere-*"
    }
%{ if var.enhanced_security_use_cmk }
    ,{
      "Sid": "AllowKmsCmk",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "${aws_kms_key.xosphere_kms_key[0].arn}"
    }
%{ endif }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_snapshot_creator_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-snapshot-creator"
  retention_in_days = var.snapshot_creator_lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_snapshot_creator_cloudwatch_event_rule" {
  name = "xosphere-snapshot-creator-schedule-event-rule"
  description = "Schedule for launching Xosphere Instance Orchestrator Snapshot Creator"
  schedule_expression = "cron(${var.snapshot_creator_cron_schedule})"
  is_enabled = true
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_snapshot_creator_cloudwatch_event_target" {
  arn = aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn
  rule = aws_cloudwatch_event_rule.instance_orchestrator_snapshot_creator_cloudwatch_event_rule.name
  target_id = "xosphere-io-snapshot-creator-schedule"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_snapshot_creator_lambda_sqs_trigger" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_snapshot_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn
}
