resource "aws_lambda_function" "xosphere_event_router_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "event-router-lambda-${local.version}.zip"
  description = "Xosphere Event Router"
  environment {
    variables = {
      TERMINATOR_QUEUE_URL = aws_sqs_queue.xosphere_terminator_queue.id
      SCHEDULER_CWE_QUEUE_URL = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_queue.id
      XOGROUP_ENABLER_QUEUE_URL = aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.id
      GROUP_INSPECTOR_QUEUE_URL = aws_sqs_queue.instance_orchestrator_group_inspector_queue.id
      ENHANCER_MODE = "false"
      ENHANCER_SQS_QUEUE_URL = aws_sqs_queue.instance_orchestrator_event_router_enhancer_queue.id
      ORGANIZATION_EC2_STATE_CHANGE_EVENT_COLLECTOR_SQS_QUEUE_URL = local.organization_management_account_enabled ? join("", ["https://sqs.", var.management_account_region, ".amazonaws.com/", var.management_aws_account_id, "/", local.wellknown__xosphere_organization_instance_state_event_collector_queue_name]) : null
      ORGANIZATION_REGION = local.organization_management_account_enabled ? var.management_account_region : null
      GROUP_INSPECTOR_NOTIFICATION_EVENT_INSTANCE_STATES = local.statemap__group_inspector
      ORGANIZATION_INVENTORY_UPDATES_SUBMITTER_ROLE_NAME = local.wellknown__xosphere_organization_inventory_updates_submitter_role
    }
  }
  function_name = "xosphere-event-router"
  handler = "bootstrap"
  memory_size = 128
  role = aws_iam_role.xosphere_event_router_iam_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = 900
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.xosphere_event_router_cloudwatch_log_group ]
}

resource "aws_lambda_event_source_mapping" "xosphere_event_router_event_source_mapping" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_event_router_queue.arn
  function_name = aws_lambda_function.xosphere_event_router_lambda.arn
  depends_on = [ aws_iam_role.xosphere_event_router_iam_role ]
}

resource "aws_lambda_permission" "xosphere_event_router_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_event_router_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_event_router_queue.arn
  statement_id = var.event_router_lambda_permission_name_override == null ? "AllowExecutionFromSqs" : var.event_router_lambda_permission_name_override
}

resource "aws_lambda_function" "xosphere_event_router_enhancer_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "event-router-lambda-${local.version}.zip"
  description = "Xosphere Event Router Enhancer"
  environment {
    variables = {
      TERMINATOR_QUEUE_URL = aws_sqs_queue.xosphere_terminator_queue.id
      SCHEDULER_CWE_QUEUE_URL = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_queue.id
      XOGROUP_ENABLER_QUEUE_URL = aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.id
      GROUP_INSPECTOR_QUEUE_URL = aws_sqs_queue.instance_orchestrator_group_inspector_queue.id
      ENHANCER_MODE = "true"
      ENHANCER_SQS_QUEUE_URL = aws_sqs_queue.instance_orchestrator_event_router_enhancer_queue.id
      ORGANIZATION_EC2_STATE_CHANGE_EVENT_COLLECTOR_SQS_QUEUE_URL = local.organization_management_account_enabled ? join("", ["https://sqs.", var.management_account_region, ".amazonaws.com/", var.management_aws_account_id, "/", local.wellknown__xosphere_organization_instance_state_event_collector_queue_name]) : null
      ORGANIZATION_REGION = local.organization_management_account_enabled ? var.management_account_region : null
      GROUP_INSPECTOR_NOTIFICATION_EVENT_INSTANCE_STATES = local.statemap__group_inspector
      ORGANIZATION_INVENTORY_UPDATES_SUBMITTER_ROLE_NAME = local.wellknown__xosphere_organization_inventory_updates_submitter_role
    }
  }
  function_name = "xosphere-event-router-enhancer"
  handler = "bootstrap"
  memory_size = 128
  role = aws_iam_role.xosphere_event_router_iam_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = 900
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.xosphere_event_router_enhancer_cloudwatch_log_group ]
}

resource "aws_lambda_event_source_mapping" "xosphere_event_router_enhancer_event_source_mapping" {
  batch_size = 100
  maximum_batching_window_in_seconds = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_event_router_enhancer_queue.arn
  function_name = aws_lambda_function.xosphere_event_router_enhancer_lambda.arn
  depends_on = [ aws_iam_role.xosphere_event_router_iam_role ]
}

resource "aws_lambda_permission" "xosphere_event_router_enhancer_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_event_router_enhancer_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_event_router_enhancer_queue.arn
  statement_id = var.event_router_enhancer_lambda_permission_name_override == null ? "AllowExecutionFromSqs" : var.event_router_enhancer_lambda_permission_name_override
}

resource "aws_iam_role" "xosphere_event_router_iam_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": {
    "Action": [ "sts:AssumeRole" ],
    "Effect": "Allow",
    "Principal": {
      "Service": [ "lambda.amazonaws.com" ]
    }
  }
}
EOF
  managed_policy_arns = [ ]
  path = "/"
  name = "xosphere-event-router-lambda-role"
  tags = var.tags
}

resource "aws_iam_role_policy" "xosphere_event_router_iam_role_policy" {
  name = "xosphere-event-router-lambda-policy"
  role = aws_iam_role.xosphere_event_router_iam_role.id
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
      "Sid": "AllowLambdaOperationsOnXosphereFunctions",
      "Effect": "Allow",
      "Action": [
		    "lambda:InvokeFunction"
	    ],
      "Resource": "arn:aws:lambda:*:*:function:xosphere-*"
    },
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
      "Resource": [
        "${aws_sqs_queue.xosphere_terminator_queue.arn}",
        "${aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_queue.arn}",
        "${aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.arn}",
        "${aws_sqs_queue.instance_orchestrator_group_inspector_queue.arn}",
        "${aws_sqs_queue.instance_orchestrator_event_router_queue.arn}",
        "${aws_sqs_queue.instance_orchestrator_event_router_enhancer_queue.arn}"
%{ if local.organization_management_account_enabled }
        ,"${join("", ["arn:*:sqs:", var.management_account_region, ":", var.management_aws_account_id, ":", local.wellknown__xosphere_organization_instance_state_event_collector_queue_name])}"
%{ endif }
      ]
    },
%{ if local.organization_management_account_enabled }
    {
      "Sid": "AllowOrgKmsCmk",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "${join("", ["arn:*:kms:*:", var.management_aws_account_id, ":key/*"])}",
      "Condition": {
        "ForAnyValue:StringEquals": {
          "kms:ResourceAliases": "alias/XosphereMgmtCmk"
        }
      }
    },
%{ endif }
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
      "Sid": "AllowDetectInventoryCollectorInstalled",
      "Effect": "Allow",
      "Action": [
		    "iam:ListRoleTags"
	    ],
      "Resource": "${join("", ["arn:aws:iam::", data.aws_caller_identity.current.account_id, ":role/", local.wellknown__xosphere_organization_inventory_updates_submitter_role])}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "xosphere_event_router_iam_role_policy_service_linked_roles" {
  name = "xosphere-event-router-lambda-policy-service-linked-roles"
  role = aws_iam_role.xosphere_event_router_iam_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaServiceLinkedRole",
      "Effect": "Allow",
      "Action": [
		"iam:CreateServiceLinkedRole"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*",
      "Condition": {
        "StringLike": {"iam:AWSServiceName": "lambda.amazonaws.com"}
      }
    },
    {
      "Sid": "AllowLambdaServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "xosphere_event_router_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-event-router"
  retention_in_days = var.event_router_lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "xosphere_event_router_enhancer_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-event-router-enhancer"
  retention_in_days = var.event_router_enhancer_lambda_log_retention
  tags = var.tags
}

resource "aws_iam_role" "xosphere_event_relay_iam_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": {
    "Action": [ "sts:AssumeRole" ],
    "Effect": "Allow",
    "Principal": {
      "Service": [ "lambda.amazonaws.com"]
    }
  }
}
EOF
  managed_policy_arns = [ ]
  path = "/"
  name = "xosphere-event-relay-lambda-role"
  tags = var.tags
}

resource "aws_iam_role_policy" "xosphere_event_relay_iam_role_policy" {
  name = "xosphere-event-relay-lambda-policy"
  role = aws_iam_role.xosphere_event_relay_iam_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
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
      "Action": [ "sqs:SendMessage" ],
      "Resource": "${aws_sqs_queue.instance_orchestrator_event_router_queue.arn}"
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

resource "aws_iam_role_policy" "xosphere_event_relay_iam_role_policy_service_linked_roles" {
  name = "xosphere-event-relay-lambda-policy-service-linked-roles"
  role = aws_iam_role.xosphere_event_relay_iam_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaServiceLinkedRole",
      "Effect": "Allow",
      "Action": [ "iam:CreateServiceLinkedRole" ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": [ "lambda.amazonaws.com" ]
        }
      }
    },
    {
      "Sid": "AllowLambdaServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*"
    }
  ]
}
EOF
}