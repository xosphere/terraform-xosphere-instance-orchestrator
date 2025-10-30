locals {
  version = "0.29.6"
  api_token_arn = (var.secretsmanager_arn_override == null) ? format("arn:aws:secretsmanager:%s:%s:secret:customer/%s", local.xo_account_region, var.xo_account_id, var.customer_id) : var.secretsmanager_arn_override
  api_token_pattern = (var.secretsmanager_arn_override == null) ? format("arn:aws:secretsmanager:%s:%s:secret:customer/%s-??????", local.xo_account_region, var.xo_account_id, var.customer_id) : var.secretsmanager_arn_override
  regions = join(",", var.regions_enabled)
  kms_key_pattern = format("arn:aws:kms:%s:%s:key/*", local.xo_account_region, var.xo_account_id)
  s3_bucket = "xosphere-io-releases-${data.aws_region.current.name}"
  xo_account_region = "us-west-2"
  has_global_terraform_settings = var.terraform_version != "" || var.terraform_aws_provider_version != "" || var.terraform_backend_aws_region != "" || var.terraform_backend_s3_bucket != "" || var.terraform_backend_s3_key != ""
  needDefineTerraformS3Permission = var.terraform_backend_s3_bucket != "" && var.terraform_backend_aws_region != ""
  needDefineTerraformDynamoDBPermission = var.terraform_backend_dynamodb_table != ""
  has_k8s_vpc_config = ((length(var.k8s_vpc_security_group_ids) > 0) && (length(var.k8s_vpc_subnet_ids) > 0))
  has_k8s_vpc_config_string = local.has_k8s_vpc_config ? "true" : "false"
  organization_management_account_enabled = var.management_account_region != "" || var.management_aws_account_id != ""

  wellknown__xosphere_event_router_lambda_role = "xosphere-event-router-lambda-role"
  wellknown__xosphere_organization_instance_state_event_collector_queue_name = "xosphere-instance-orchestrator-org-inst-state-event-collector-launch"
  wellknown__xosphere_organization_inventory_updates_submitter_role = "xosphere-instance-orchestrator-org-inv-upd-sub-assume-role"

  statemap__group_inspector = "pending,terminated,running,stopping"
  statemap__org_inventory_and_group_inspector = "pending,terminated,running,stopping,stopped"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "instance_state_s3_logging_bucket" {
  count = var.create_logging_buckets ? 1 : 0
  force_destroy = true
  bucket_prefix = var.logging_bucket_name_override == null ? "xosphere-io-logging" : null
  bucket = var.logging_bucket_name_override == null ? null : var.logging_bucket_name_override
  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "instance_state_s3_logging_bucket_sse" {
  count  = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enhanced_security_use_cmk ? "aws:kms" : "AES256"
      kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : null
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "instance_state_s3_logging_lifecycle" {
  count  = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id

  rule {
    id     = "TransitionToGlacierThenDelete"
    status = "Enabled"

    filter {
      prefix = "" # Applies to all objects
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "instance_state_s3_logging_bucket_policy" {
  count = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*",
      "Principal": {
        "Service": "logging.s3.amazonaws.com"
      },
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.instance_state_s3_bucket.arn}"
        },
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    },
    {
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    },
    {
      "Sid": "RequireSecureTransport",
      "Action": "s3:*",
      "Effect": "Deny",
      "Resource": [
        "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}",
        "${aws_s3_bucket.instance_state_s3_logging_bucket[0].arn}/*"
      ],
      "Principal": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "instance_state_s3_logging_bucket_public_access_block" {
  count = var.create_logging_buckets ? 1 : 0
  bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "instance_state_s3_bucket" {
  force_destroy = true
  bucket_prefix = var.state_bucket_name_override == null ? "xosphere-instance-orchestrator" : null
  bucket = var.state_bucket_name_override == null ? null : var.state_bucket_name_override
  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "instance_state_s3_bucket_sse" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enhanced_security_use_cmk ? "aws:kms" : "AES256"
      kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : null
    }
  }
}

resource "aws_s3_bucket_logging" "instance_state_s3_bucket_logging" {
  count = var.create_logging_buckets ? 1 : 0

  bucket        = aws_s3_bucket.instance_state_s3_bucket.id
  target_bucket = aws_s3_bucket.instance_state_s3_logging_bucket[0].id
  target_prefix = "xosphere-instance-orchestrator-logs"
}

resource "aws_s3_bucket_lifecycle_configuration" "instance_state_s3_bucket_lifecycle" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id

  rule {
    id     = "DeleteAfter2Years"
    status = "Enabled"

    filter {
      prefix = "" # Applies to all objects
    }

    expiration {
      days = 730
    }
  }
}

resource "aws_s3_bucket_policy" "instance_state_s3_bucket_policy" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.instance_state_s3_bucket.arn}/*",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    },
    {
      "Sid": "RequireSecureTransport",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": [
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
      ],
      "Principal": "*",
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "instance_state_s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.instance_state_s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sqs_queue" "instance_orchestrator_launcher_dlq" {
  name = "xosphere-instance-orchestrator-launch-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_launcher_queue" {
  name = "xosphere-instance-orchestrator-launch"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_launcher_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_dlq" {
  name = "xosphere-instance-orchestrator-event-router-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_queue" {
  name = "xosphere-instance-orchestrator-event-router"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_event_router_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_enhancer_dlq" {
  name = "xosphere-instance-orchestrator-event-router-enhancer-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_enhancer_queue" {
  name = "xosphere-instance-orchestrator-event-router-enhancer"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_event_router_enhancer_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_dlq" {
  name = "xosphere-instance-orchestrator-schedule-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_queue" {
  name = "xosphere-instance-orchestrator-schedule"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_schedule_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_dlq" {
  name = "xosphere-instance-orchestrator-snapshot-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_queue" {
  name = "xosphere-instance-orchestrator-snapshot"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_snapshot_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_budget_dlq" {
  name = "xosphere-instance-orchestrator-budget-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_budget_queue" {
  name = "xosphere-instance-orchestrator-budget"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_budget_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_group_inspector_dlq" {
  name = "xosphere-instance-orchestrator-group-inspector-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_group_inspector_queue" {
  name = "xosphere-instance-orchestrator-group-inspector"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_group_inspector_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_scheduler_cloudwatch_event_dlq" {
  name = "xosphere-instance-orchestrator-schedule-cwe-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_scheduler_cloudwatch_event_queue" {
  name = "xosphere-instance-orchestrator-schedule-cwe"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "xosphere_terminator_dlq" {
  name = "xosphere-instance-orchestrator-terminator-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "xosphere_terminator_queue" {
  name = "xosphere-instance-orchestrator-terminator"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.xosphere_terminator_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_xogroup_enabler_dlq" {
  name = "xosphere-instance-orchestrator-xogroup-enabler-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_xogroup_enabler_queue" {
  name = "xosphere-instance-orchestrator-xogroup-enabler"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_xogroup_enabler_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}


//event router
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

//terminator
resource "aws_lambda_function" "xosphere_terminator_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "terminator-lambda-${local.version}.zip"
  description = "Xosphere Terminator"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_queue.id
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      IO_BRIDGE_NAME = "xosphere-io-bridge"
      K8S_VPC_ENABLED = local.has_k8s_vpc_config_string
      K8S_POD_EVICTION_GRACE_PERIOD = var.k8s_pod_eviction_grace_period
      ATTACHER_NAME = aws_lambda_function.instance_orchestrator_attacher_lambda.function_name
      IGNORE_LB_HEALTH_CHECK = var.ignore_lb_health_check      
    }
  }
  function_name = "xosphere-terminator-lambda"
  handler = "bootstrap"
  memory_size = var.terminator_lambda_memory_size
  role = aws_iam_role.xosphere_terminator_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.terminator_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.xosphere_terminator_cloudwatch_log_group ]
}

resource "aws_iam_role" "xosphere_terminator_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaToAssumeRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" }
    }
  ]
}
EOF
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn, aws_iam_policy.create_fleet_managed_policy.arn ]  
  name = "xosphere-terminator-lambda-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "xosphere_terminator_policy" {
  name = "xosphere-terminator-lambda-policy"
  role = aws_iam_role.xosphere_terminator_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeNotificationConfigurations",
        "autoscaling:DescribeScalingActivities",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstances",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:ModifyInstanceAttribute",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DescribeInstanceHealth"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:EnterStandby",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {"autoscaling:ResourceTag/xosphere.io/instance-orchestrator/enabled": "true"}
      }
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:EnterStandby",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {"autoscaling:ResourceTag/xosphere:instance-orchestrator:enabled": "true"}
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:TerminateInstances"
	  ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:TerminateInstances"
	  ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:TerminateInstances",
        "ec2:ModifyNetworkInterfaceAttribute"
	    ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:TerminateInstances",
        "ec2:ModifyNetworkInterfaceAttribute"
	    ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEcsClusterOperations",
      "Effect": "Allow",
      "Action": [
        "ecs:ListContainerInstances"
      ],
      "Resource": "arn:*:ecs:*:*:cluster/*"

    },
    {
      "Sid": "AllowPassRoleOnXosphereRolesToXosphereLambdaFunctions",
      "Effect": "Allow",
      "Action": [
    		"iam:PassRole"
	    ],
      "Resource": "arn:aws:iam::*:role/xosphere-*",
      "Condition": {
        "StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"},
      	"StringLike": {
            "iam:AssociatedResourceARN": [
                "arn:aws:lambda:*:*:function:xosphere-*"
            ]
        }
      }
    },
    {
      "Action": [
        "iam:PassRole"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      },
      "Effect": "Allow",
      "Resource": "*",
      "Sid": "AllowPassRoleToEc2Instances"
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
		    "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging"
      ],
      "Resource": [
        "arn:aws:s3:::xosphere-*/*",
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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
        "Sid": "AllowSnsOperationsOnXosphereTopics",
        "Effect": "Allow",
        "Action": [
            "sns:Publish"
        ],
        "Resource": "${var.sns_arn_resource_pattern}"
    },
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
    },
    {
        "Sid": "AllowSqsConsumeOnTerminatorQueue",
        "Effect": "Allow",
        "Action": [
            "sqs:ChangeMessageVisibility",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:ReceiveMessage",
            "sqs:SendMessage"
        ],
        "Resource": [
          "${aws_sqs_queue.xosphere_terminator_queue.arn}"
        ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "xosphere_terminator_policy_service_linked_roles" {
  name = "xosphere-terminator-lambda-policy-service-linked-roles"
  role = aws_iam_role.xosphere_terminator_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
      "Sid": "AllowAutoScalingServiceLinkedRole",
      "Effect": "Allow",
      "Action": ["iam:CreateServiceLinkedRole"],
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
    },
	{
      "Sid": "AllowLambdaServiceLinkedRole",
      "Effect": "Allow",
      "Action": ["iam:CreateServiceLinkedRole"],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": ["lambda.amazonaws.com"]}}
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

resource "aws_cloudwatch_log_group" "xosphere_terminator_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-terminator-lambda"
  retention_in_days = var.terminator_lambda_log_retention
  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "xosphere_terminator_event_source_mapping" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.xosphere_terminator_queue.arn
  function_name = aws_lambda_function.xosphere_terminator_lambda.arn
  depends_on = [ aws_iam_role.xosphere_terminator_role ]
}

resource "aws_lambda_permission" "xosphere_terminator_sqs_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_terminator_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.xosphere_terminator_queue.arn
  statement_id = var.xosphere_terminator_sqs_lambda_permission_name_override == null ? "AllowExecutionFromSqs" : var.xosphere_terminator_sqs_lambda_permission_name_override
}

//instance-orchestrator
resource "aws_lambda_function" "xosphere_instance_orchestrator_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "instance-orchestrator-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator"
  environment {
    variables = {
      REGIONS = local.regions
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_queue.id
      SQS_SCHEDULER_QUEUE = aws_sqs_queue.instance_orchestrator_schedule_queue.id
      SQS_SNAPSHOT_QUEUE = aws_sqs_queue.instance_orchestrator_snapshot_queue.id
      ENABLE_CLOUDWATCH = var.enable_cloudwatch
      IO_BRIDGE_NAME = local.has_k8s_vpc_config ? aws_lambda_function.xosphere_io_bridge_lambda[0].id : "xosphere-io-bridge"
      ATTACHER_NAME = aws_lambda_function.instance_orchestrator_attacher_lambda.function_name
      K8S_VPC_ENABLED = local.has_k8s_vpc_config_string
      K8S_DRAIN_TIMEOUT_IN_MINS = var.k8s_drain_timeout_in_mins
      K8S_POD_EVICTION_GRACE_PERIOD = var.k8s_pod_eviction_grace_period
      RESERVED_INSTANCES_REGIONAL_BUFFER = var.reserved_instances_regional_buffer
      RESERVED_INSTANCES_AZ_BUFFER = var.reserved_instances_az_buffer
      EC2_INSTANCE_SAVINGS_PLAN_BUFFER = var.ec2_instance_savings_plan_buffer
      COMPUTE_SAVINGS_PLAN_BUFFER = var.compute_savings_plan_buffer
      ORGANIZATION_DATA_S3_BUCKET = local.organization_management_account_enabled ? var.management_account_data_bucket : null
      ORGANIZATION_REGION = local.organization_management_account_enabled ? var.management_account_region : null
      ENABLE_CODEDEPLOY = var.enable_code_deploy_integration
      IGNORE_LB_HEALTH_CHECK = var.ignore_lb_health_check
    }
  }
  function_name = "xosphere-instance-orchestrator-lambda"
  handler = "bootstrap"
  memory_size = var.lambda_memory_size
  role = aws_iam_role.xosphere_instance_orchestrator_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.lambda_timeout
  tags = var.tags
  reserved_concurrent_executions = 1
}

resource "aws_lambda_function_event_invoke_config" "xosphere_instance_orchestrator_lambda_invoke_config" {
  function_name = aws_lambda_function.xosphere_instance_orchestrator_lambda.function_name
  maximum_retry_attempts = 0
  maximum_event_age_in_seconds = null
  qualifier = "$LATEST"
}

resource "aws_lambda_permission" "xosphere_instance_orchestrator_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_instance_orchestrator_lambda.arn
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.xosphere_instance_orchestrator_cloudwatch_event_rule.arn
  statement_id = var.orchestrator_lambda_permission_name_override == null ? "AllowExecutionFromEventBridge" : var.orchestrator_lambda_permission_name_override
}

resource "aws_iam_role" "xosphere_instance_orchestrator_role" {
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
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn, aws_iam_policy.create_fleet_managed_policy.arn, aws_iam_policy.instance_orchestrator_ec2_managed_policy.arn ]
  name = "xosphere-instance-orchestrator-lambda-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "xosphere_instance_orchestrator_policy" {
  name = "xosphere-instance-orchestrator-lambda-policy"
  role = aws_iam_role.xosphere_instance_orchestrator_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeInstanceRefreshes",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeLifecycleHooks",
        "autoscaling:DescribeLoadBalancers",
        "autoscaling:DescribeLoadBalancerTargetGroups",
        "autoscaling:DescribeNotificationConfigurations",
        "autoscaling:DescribePolicies",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeScheduledActions",
        "autoscaling:DescribeTags",
        "eks:DescribeNodegroup",
        "elasticloadbalancing:DescribeInstanceHealth",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "organizations:DescribeOrganization",
        "savingsplans:DescribeSavingsPlans",
        "savingsplans:DescribeSavingsPlanRates"
      ],
      "Resource": "*"
    },
%{ if var.enable_code_deploy_integration }
    {
      "Sid": "AllowCodeDeployOperations",
      "Effect": "Allow",
      "Action": [
        "codedeploy:BatchGetDeploymentGroups",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:GetDeploymentGroup",
        "codedeploy:ListApplications",
        "codedeploy:ListDeploymentGroups"
      ],
      "Resource": "*"
    },
%{ endif }
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:BatchPutScheduledUpdateGroupAction",
        "autoscaling:BatchDeleteScheduledAction",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
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
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:BatchPutScheduledUpdateGroupAction",
        "autoscaling:BatchDeleteScheduledAction",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {
          "autoscaling:ResourceTag/xosphere:instance-orchestrator:enabled": "true"
        }
      }
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
      "Sid": "AllowEcsClusterReadOperations",
      "Effect": "Allow",
      "Action": [
        "ecs:ListContainerInstances"
	  ],
      "Resource": "arn:*:ecs:*:*:cluster/*"
    },
    {
      "Sid": "AllowPassRoleOnXosphereRolesToXosphereLambdaFunctions",
      "Effect": "Allow",
      "Action": [
		"iam:PassRole"
	  ],
      "Resource": "arn:aws:iam::*:role/xosphere-*",
      "Condition": {
        "StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"},
      	"StringLike": {
            "iam:AssociatedResourceARN": [
                "arn:aws:lambda:*:*:function:xosphere-*"
            ]
        }
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
      "Sid": "AllowLambdaOperationsOnXosphereFunctions",
      "Effect": "Allow",
      "Action": [
		"lambda:InvokeFunction"
	  ],
      "Resource": "arn:aws:lambda:*:*:function:xosphere-*"
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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
        "Sid": "AllowSnsOperationsOnXosphereTopics",
        "Effect": "Allow",
        "Action": [
            "sns:Publish"
        ],
        "Resource": "${var.sns_arn_resource_pattern}"
    },
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
    },
    {
      "Sid": "AllowPassRoleToCodeDeploy",
      "Effect": "Allow",
      "Action": [
		"iam:PassRole"
	  ],
      "Resource": "${var.codedeploy_passrole_arn_resource_pattern}",
      "Condition": {
        "StringEquals": {"iam:PassedToService": "codedeploy.amazonaws.com"}
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "xosphere_instance_orchestrator_policy_service_linked_roles" {
  name = "xosphere-instance-orchestrator-lambda-policy-service-linked-roles"
  role = aws_iam_role.xosphere_instance_orchestrator_role.id
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
    },
	{
      "Sid": "AllowLambdaServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": ["lambda.amazonaws.com"]}}
    },
    {
      "Sid": "AllowLambdaServiceLinkedRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/lambda.amazonaws.com/*"
    },
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
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "xosphere_instance_orchestrator_policy_additional" {
  name = "xosphere-instance-orchestrator-lambda-policy-additional"
  role = aws_iam_role.xosphere_instance_orchestrator_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCodeDeployOperations",
      "Effect": "Allow",
      "Action": [
        "codedeploy:CreateDeployment", %{ if false } # safe - the danger is if/when we attach it %{ endif }
        "codedeploy:UpdateDeploymentGroup" %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
	  ],
      "Resource": "*"
    },
    {
      "Sid": "AllowLoadBalancingOperations",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:DeregisterTargets" %{ if false } # # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
	  ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEcsClusterUpdateOperations",
      "Effect": "Allow",
      "Action": [
        "ecs:DeregisterContainerInstance" %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
  	  ],
      "Resource": "arn:*:ecs:*:*:cluster/*"
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEksNodeGroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateOrUpdateTags"
  	  ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "ForAllValues:StringLike": {
          "aws:ResourceTag/eks:nodegroup-name": [ "*" ],
          "aws:ResourceTag/eks:cluster-name": [ "*" ]
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": [
            "xosphere.io/instance-orchestrator/enabled"
          ]
        }
      }
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEksNodeGroupsColons",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateOrUpdateTags"
  	  ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "ForAllValues:StringLike": {
          "aws:ResourceTag/eks:nodegroup-name": [ "*" ],
          "aws:ResourceTag/eks:cluster-name": [ "*" ]
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": [
            "xosphere:instance-orchestrator:enabled"
          ]
        }
      }
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "xosphere_instance_orchestrator_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-lambda"
  retention_in_days = var.lambda_log_retention
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "xosphere_instance_orchestrator_cloudwatch_event_rule" {
  name = "xosphere-instance-orchestrator-schedule-event-rule"
  description = "Schedule for launching Instance Orchestrator"
  schedule_expression = "cron(${var.lambda_cron_schedule})"
  is_enabled = true
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "xosphere_instance_orchestrator_cloudwatch_event_target" {
  arn = aws_lambda_function.xosphere_instance_orchestrator_lambda.arn
  rule = aws_cloudwatch_event_rule.xosphere_instance_orchestrator_cloudwatch_event_rule.name
  target_id = aws_sqs_queue.instance_orchestrator_schedule_queue.name
}

//launcher
resource "aws_lambda_function" "xosphere_instance_orchestrator_launcher_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "launcher-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Launcher"
  environment {
    variables = {
      API_TOKEN_ARN = local.api_token_arn
      ENDPOINT_URL = var.endpoint_url
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_launcher_queue.id
      SQS_SNAPSHOT_QUEUE: aws_sqs_queue.instance_orchestrator_snapshot_queue.id
      HAS_GLOBAL_TERRAFORM_SETTING = local.has_global_terraform_settings ? "true" : "false"
      TERRAFORMER_LAMBDA_NAME = aws_lambda_function.instance_orchestrator_terraformer_lambda.function_name
    }
  }
  function_name = "xosphere-instance-orchestrator-launcher"
  handler = "bootstrap"
  memory_size = var.io_launcher_memory_size
  role = aws_iam_role.instance_orchestrator_launcher_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_launcher_lambda_timeout
  reserved_concurrent_executions = 20
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_launcher_cloudwatch_log_group ]
  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_launcher_lambda_sqs_trigger" {
  event_source_arn = aws_sqs_queue.instance_orchestrator_launcher_queue.arn
  function_name = aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn
  batch_size = 1
  enabled = true
}

resource "aws_lambda_permission" "instance_orchestrator_launcher_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_launcher_queue.arn
  statement_id = var.launcher_lambda_permission_name_override == null ? "AllowSQSInvoke" : var.launcher_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_launcher_lambda_role" {
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
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn, aws_iam_policy.launcher_managed_policy.arn ]
  name = "xosphere-instance-orchestrator-launcher-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_launcher_lambda_policy" {
  name = "xosphere-instance-orchestrator-launcher-policy"
  role = aws_iam_role.instance_orchestrator_launcher_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeTags",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes",
        "ec2:DescribeNetworkInterfaces",
        "elasticloadbalancing:DescribeInstanceHealth",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImageSnapshotSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImageSnapshotColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImageSnapshotSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImageSnapshotColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageOnEnabledInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageOnEnabledInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageXoGroupInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageXoGroupInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RegisterImageWithXosphereDescriptionImage",
      "Effect": "Allow",
      "Action": [
        "ec2:RegisterImage"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*"
      ]
    },
    {
      "Sid": "AllowEc2RegisterImageWithXoGroupTagSnapshotSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RegisterImage"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2RegisterImageWithXoGroupTagSnapshotColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RegisterImage"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsWithXosphereDescriptionImage",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:Attribute/Description": [
            "Generated for Xosphere-Instance-Orchestrator"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshotEnabledSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshotEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshotXoGroupSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshotXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshotsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": [
            "CreateImage"
          ]
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshotsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": [
            "CreateImage"
          ]
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
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
      "Sid": "AllowEc2OperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:ModifyNetworkInterfaceAttribute"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:ModifyNetworkInterfaceAttribute"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
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
      "Sid": "AllowLambdaOperationsOnXosphereFunctions",
      "Effect": "Allow",
      "Action": [
		    "lambda:InvokeFunction"
	    ],
      "Resource": "arn:aws:lambda:*:*:function:xosphere-*"
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
      ]
    },
    {
        "Sid": "AllowSnsOperationsOnXosphereTopics",
        "Effect": "Allow",
        "Action": [
            "sns:Publish"
        ],
        "Resource": "${var.sns_arn_resource_pattern}"
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

resource "aws_iam_role_policy" "instance_orchestrator_launcher_lambda_policy_service_linked_roles" {
  name = "xosphere-instance-orchestrator-launcher-policy-service-linked-roles"
  role = aws_iam_role.instance_orchestrator_launcher_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEC2SpotServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/*",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": [
            "spot.amazonaws.com"
          ]
        }
      }
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
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": [
            "elasticloadbalancing.amazonaws.com"
          ]
        }
      }
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

resource "aws_cloudwatch_log_group" "instance_orchestrator_launcher_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-launcher"
  retention_in_days = var.io_launcher_lambda_log_retention
  tags = var.tags
}

//scheduler

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
      "Sid": "AllowEc2OperationsOnSchedulesSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/schedule-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnSchedulesColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:schedule-name": ["*"]
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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

resource "aws_lambda_event_source_mapping" "instance_orchestrator_scheduler_cloudwatch_event_sqs_trigger" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_scheduler_cloudwatch_event_lambda.arn
  depends_on = [ aws_iam_role.instance_orchestrator_scheduler_lambda_role ]
}

resource "aws_lambda_permission" "instance_orchestrator_scheduler_cloudwatch_event_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_scheduler_cloudwatch_event_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_queue.arn
  statement_id = var.scheduler_cwe_lambda_permission_name_override == null ? "AllowExecutionFromSqs" : var.scheduler_cwe_lambda_permission_name_override
}

// Xogroup enabler

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
      "Sid": "AllowEc2OperationsOnXogroupInstancesSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags"
      ],
      "Resource": [ "*" ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupInstancesColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags"
      ],
      "Resource": [ "*" ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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

resource "aws_lambda_event_source_mapping" "instance_orchestrator_xogroup_enabler_event_source_mapping" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_xogroup_enabler_lambda.arn
  depends_on = [ aws_iam_role.instance_orchestrator_xogroup_enabler_lambda_role ]
}

resource "aws_lambda_permission" "instance_orchestrator_xogroup_enabler_sqs_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_xogroup_enabler_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_xogroup_enabler_queue.arn
  statement_id = var.xogroup_enabler_lambda_permission_name_override == null ? "AllowExecutionFromSqs" : var.xogroup_enabler_lambda_permission_name_override
}

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
      "Sid": "AllowEc2CreateTagsSlashes",
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
    {
      "Sid": "AllowEc2CreateTagsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
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
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "autoscaling:ResourceTag/xosphere.io/instance-orchestrator/budget-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "autoscaling:ResourceTag/xosphere:instance-orchestrator:budget-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnBudgetsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/budget-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnBudgetsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:budget-name": ["*"]
        }
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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

// budget processor

resource "aws_lambda_function" "instance_orchestrator_budget_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "budget-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Budget"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      SQS_QUEUE = aws_sqs_queue.instance_orchestrator_budget_queue.id
    }
  }
  function_name = "xosphere-instance-orchestrator-budget"
  handler = "bootstrap"
  memory_size = var.io_budget_memory_size
  role = aws_iam_role.instance_orchestrator_budget_lambda_role.arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  timeout = var.io_budget_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.instance_orchestrator_budget_cloudwatch_log_group ]
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_budget_lambda_sqs_trigger" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_budget_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_budget_lambda.arn
  depends_on = [ aws_iam_role.instance_orchestrator_budget_lambda_role ]
}

resource "aws_lambda_permission" "instance_orchestrator_budget_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_budget_lambda.arn
  principal = "sqs.amazonaws.com"
  source_arn = aws_sqs_queue.instance_orchestrator_budget_queue.arn
  statement_id = var.budget_lambda_permission_name_override == null ? "AllowSQSInvoke" : var.budget_lambda_permission_name_override
}

resource "aws_iam_role" "instance_orchestrator_budget_lambda_role" {
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
  name = "xosphere-instance-orchestrator-budget-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "instance_orchestrator_budget_lambda_policy" {
  name = "xosphere-instance-orchestrator-budget-policy"
  role = aws_iam_role.instance_orchestrator_budget_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:DescribeInstanceStatus",
        "elasticloadbalancing:DescribeInstanceHealth",
        "elasticloadbalancing:DescribeTargetHealth"
       ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEc2OperationsOnBudgetsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/budget-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnBudgetsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:budget-name": ["*"]
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "instance_orchestrator_budget_lambda_policy_service_linked_roles" {
  name = "xosphere-instance-orchestrator-budget-policy-service-linked-roles"
  role = aws_iam_role.instance_orchestrator_budget_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
      "Sid": "AllowElasticLoadBalancingServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/*",
      "Condition": {"StringLike": {"iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"}}
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

resource "aws_iam_role_policy" "instance_orchestrator_budget_lambda_policy_additional" {
  name = "xosphere-instance-orchestrator-budget-policy-additional"
  role = aws_iam_role.instance_orchestrator_budget_lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLoadBalancingOperations",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:DeregisterTargets", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:RegisterTargets" %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
	  ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_budget_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-budget"
  retention_in_days = var.io_budget_lambda_log_retention
  tags = var.tags
}

//snapshot

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
      "Sid": "AllowEc2CreateSnapshotSnapshotSlashes",
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
      "Sid": "AllowEc2CreateSnapshotSnapshotColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
	  ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshotsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateSnapshot"
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshotsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateSnapshot"
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": "*"
        }
      }
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeleteSnapshotXoGroupSlashes",
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
    {
      "Sid": "AllowEc2DeleteSnapshotXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": [
        "arn:aws:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
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
      "Sid": "AllowEc2CreateTagsSlashes",
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
    {
      "Sid": "AllowEc2CreateTagsColons",
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
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
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

// Group Inspector

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
      SCHEDULER_QUEUE_URL = aws_sqs_queue.instance_orchestrator_schedule_queue.id
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
        "Resource": [
            "${aws_sqs_queue.instance_orchestrator_group_inspector_queue.arn}",
            "${aws_sqs_queue.instance_orchestrator_schedule_queue.arn}"
        ]
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

resource "aws_lambda_event_source_mapping" "instance_orchestrator_group_inspector_event_source_mapping" {
  batch_size = 1
  enabled = true
  event_source_arn = aws_sqs_queue.instance_orchestrator_group_inspector_queue.arn
  function_name = aws_lambda_function.instance_orchestrator_group_inspector_lambda.arn
  depends_on = [ aws_iam_role.instance_orchestrator_group_inspector_role ]
}


//AMI cleaner

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
      "Sid": "AllowEc2DeregisterImageOnEnabledSlashes",
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
      "Sid": "AllowEc2DeregisterImageOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2DeregisterImageXoGroupSlashes",
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
    {
      "Sid": "AllowEc2DeregisterImageXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
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
      "Sid": "AllowEc2DeleteSnapshotXoGroupSlashes",
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
    {
      "Sid": "AllowEc2DeleteSnapshotXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteSnapshot"
      ],
      "Resource": "arn:aws:ec2:*::snapshot/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
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

//DLQ handler

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
      "Sid": "AllowEc2CreateTagsOnXogroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsOnXogroupsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsOnXogroupInstanceFailureIdSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-instance-failure-id": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsOnXogroupInstanceFailureIdColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-instance-failure-id": ["*"]
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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

//IO Bridge

resource "aws_lambda_function" "xosphere_io_bridge_lambda" {
  count = local.has_k8s_vpc_config ? 1 : 0

  s3_bucket = local.s3_bucket
  s3_key = "iobridge-lambda-${local.version}.zip"
  description = "Xosphere Io-Bridge"
  environment {
    variables = {
      PORT = "31716"

    }
  }
  function_name = "xosphere-io-bridge"
  handler = "bootstrap"
  memory_size = var.io_bridge_memory_size
  role = aws_iam_role.io_bridge_lambda_role[count.index].arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  vpc_config {
    security_group_ids = var.k8s_vpc_security_group_ids
    subnet_ids = var.k8s_vpc_subnet_ids
  }
  timeout = var.io_bridge_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.io_bridge_cloudwatch_log_group ]
}

resource "aws_iam_role" "io_bridge_lambda_role" {
  count = local.has_k8s_vpc_config ? 1 : 0

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
  name = "xosphere-iobridge-lambda-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "io_bridge_lambda_policy" {
  count = local.has_k8s_vpc_config ? 1 : 0

  name = "xosphere-iobridge-lambda-policy"
  role = aws_iam_role.io_bridge_lambda_role[count.index].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces"
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
      "Sid": "AllowLambdaVpcExecution",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses"
      ],
      "Resource": [
        "*"
      ],
      "Condition": {
        "ForAllValues:StringEquals": {
          "ec2:SubnetID": [ "${join("\",\"", var.k8s_vpc_subnet_ids)}" ],
          "ec2:SecurityGroupID": [ "${join("\",\"", var.k8s_vpc_security_group_ids)}" ]
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_policy" "run_instances_managed_policy" {
  name        = "xosphere-instance-orchestrator-RunInstances-policy"
  description = "Policy to allow RunInstances and associated API calls"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{ if var.enhanced_security_tag_restrictions }
    {
      "Sid": "AllowEc2RunInstancesSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnXoGroupSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnEnabledSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
%{ else }
    {
      "Sid": "AllowEc2RunInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "*"
    },
%{ endif }
    {
      "Sid": "AllowEc2RunInstancesElasticInference",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ]
    },
    {
      "Sid": "AllowEc2RunInstancesOnEnabledInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnEnabledInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesXoGroupInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesXoGroupInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesOnEnabledSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "RunInstances"
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "RunInstances"
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesXoGroupSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "RunInstances"
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "RunInstances"
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowUseKmsOnAuthorizedSlashes",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": [
        "arn:*:kms:*:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowUseKmsOnAuthorizedColons",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": [
        "arn:*:kms:*:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere:instance-orchestrator:authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowSsmReadPublicParameters",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:*:ssm:*::parameter/aws/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "create_fleet_managed_policy" {
  name        = "xosphere-instance-orchestrator-CreateFleet-policy"
  description = "Policy to allow CreateFleet and associated API calls"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEc2CreateFleet",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEc2CreateFleetElasticInference",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ]
    },
    {
      "Sid": "AllowEc2CreateFleetOnEnabledInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateFleetOnEnabledInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateFleetXoGroupInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateFleetXoGroupInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetOnEnabledSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateFleet"
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateFleet"
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetXoGroupSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateFleet"
        },
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:volume/*",
        "arn:*:ec2:*:*:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateFleet"
        },
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowUseKmsOnAuthorizedSlashes",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": [
        "arn:*:kms:*:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowUseKmsOnAuthorizedColons",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": [
        "arn:*:kms:*:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere:instance-orchestrator:authorized": "true"
        }
      }
    },
    {
      "Sid": "AllowSsmReadPublicParameters",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:*:ssm:*::parameter/aws/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "instance_orchestrator_ec2_managed_policy" {
  name        = "xosphere-instance-orchestrator-ec2-managed-policy"
  description = "Policy for EC2 permissions for Instance Orchestrator Lambda"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEc2OperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplateVersion",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRegions",
        "ec2:DescribeReservedInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroupsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImageSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImageColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImageSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImageColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageOnEnabledInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageOnEnabledInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageXoGroupInstanceSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageXoGroupInstanceColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2CreateTagsOnEnabledSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": ["*"]
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
      "Sid": "AllowEc2CreateTagsOnXogroupsSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsOnXogroupsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": ["*"]
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_policy" "launcher_managed_policy" {
  name        = "xosphere-instance-orchestrator-launcher-managed-policy"
  description = "Policy for Launcher"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEc2OperationsOnVolumes",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteVolume"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowUpdateOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:AssociateAddress",
        "ec2:ModifyInstanceAttribute"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowLoadBalancingOperations",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:DeregisterTargets", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer", %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
        "elasticloadbalancing:RegisterTargets" %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
      ],
      "Resource": "*"
    },
    %{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeregisterImageOnEnabledSlashes",
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
      "Sid": "AllowEc2DeregisterImageOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2DeregisterImageXoGroupSlashes",
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
    {
      "Sid": "AllowEc2DeregisterImageXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:DeregisterImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
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
      "Sid": "AllowEc2CreateTagsOnEnabledSlashes",
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
    {
      "Sid": "AllowEc2CreateTagsOnEnabledColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsXoGroupSlashes",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
    {
      "Sid": "AllowEc2CreateTagsXoGroupColons",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:xogroup-name": "*"
        }
      }
    }
%{ else }
    {
      "Sid": "AllowEc2CreateTags",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
%{ endif }
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

resource "aws_lambda_permission" "xosphere_io_bridge_permission" {
  count = local.has_k8s_vpc_config ? 1 : 0

  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_io_bridge_lambda[0].arn
  principal = "lambda.amazonaws.com"
  source_arn = aws_lambda_function.xosphere_instance_orchestrator_lambda.arn
  statement_id = var.io_bridge_permission_name_override == null ? "AllowExecutionFromLambda" : var.io_bridge_permission_name_override
}

resource "aws_cloudwatch_log_group" "io_bridge_cloudwatch_log_group" {
  count = local.has_k8s_vpc_config ? 1 : 0

  name = "/aws/lambda/xosphere-io-bridge"
  retention_in_days = var.io_bridge_lambda_log_retention
  tags = var.tags
}

resource "aws_kms_key" "xosphere_kms_key" {
  count = var.enhanced_security_use_cmk ? 1 : 0
  description             = "Xosphere KSM CMK key"
  enable_key_rotation = true
  deletion_window_in_days = 20
  policy = jsonencode({
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = join("", ["arn:aws:iam::", data.aws_caller_identity.current.account_id, ":root"])
        }
        Resource = "*" # '*' here means "this kms key" https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
        Sid      = "Delegate permission to root user"
      },
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Resource = "*" # '*' here means "this kms key" https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
        Sid      = "S3 Access logging"
      }
    ]
    Version = "2012-10-17"
  })
}

resource "aws_kms_alias" "xosphere_kms_key_alias" {
  count = var.enhanced_security_use_cmk ? 1 : 0
  name          = "alias/XosphereKmsKey"
  target_key_id = aws_kms_key.xosphere_kms_key[0].key_id
}

// Terraformer

resource "aws_lambda_function" "instance_orchestrator_terraformer_lambda" {
  s3_bucket = local.s3_bucket
  s3_key = "terraformer-lambda-${local.version}.zip"
  description = "Xosphere Instance Orchestrator Terraformer"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = aws_s3_bucket.instance_state_s3_bucket.id
      TERRAFORM_VERSION = var.terraform_version
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
  role = aws_iam_role.instance_orchestrator_terraformer_lambda_role.arn
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
  name = "xosphere-instance-orchestrator-terraformer-policy"
  role = aws_iam_role.instance_orchestrator_terraformer_lambda_role.id
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
        "arn:aws:s3:::xosphere-*",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}",
        "${aws_s3_bucket.instance_state_s3_bucket.arn}/*"
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
      "Sid": "S3BucketMetaWhenAuthorized",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "S3BucketMetaWhenAuthorizedColon",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/xosphere:instance-orchestrator:authorized": "true"
        }
      }
    },
    {
      "Sid": "S3StateAccessWhenAuthorized",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "s3:ExistingObjectTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "S3StateAccessWhenAuthorizedColon",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "s3:ExistingObjectTag/xosphere:instance-orchestrator:authorized": "true"
        }
      }
    },
    {
      "Sid": "TerraformLockTableAccessWhenAuthorized",
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "dynamodb:ResourceTag/xosphere.io/instance-orchestrator/authorized": "true"
        }
      }
    },
    {
      "Sid": "TerraformLockTableAccessWhenAuthorizedColon",
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "dynamodb:ResourceTag/xosphere:instance-orchestrator:authorized": "true"
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

resource "aws_lambda_permission" "instance_orchestrator_terraformer_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_orchestrator_terraformer_lambda.arn
  principal = "lambda.amazonaws.com"
  source_arn = aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn
  statement_id = var.instance_orchestrator_terraformer_lambda_permission_name_override == null ? "AllowExecutionFromLambda" : var.instance_orchestrator_terraformer_lambda_permission_name_override
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_terraformer_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-terraformer"
  retention_in_days = var.terraformer_lambda_log_retention
  tags = var.tags
}

// Attacher
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
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsSlashes",
      "Effect": "Allow",
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
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
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {
          "autoscaling:ResourceTag/xosphere:instance-orchestrator:enabled": "true"
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnEnabledAsgsSlashes",
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
      "Sid": "AllowEc2OperationsOnEnabledAsgsColons",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere:instance-orchestrator:enabled": "*"
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
      "Sid": "AllowReadOperationsOnXosphereLambdas",
      "Effect": "Allow",
      "Action": [
        "lambda:Get*",
        "lambda:List*"
      ],
      "Resource": "arn:aws:lambda:*:*:function:xosphere-*"
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

output "event_relay_iam_role_arn" {
  value = aws_iam_role.xosphere_event_relay_iam_role.arn
}

output "event_router_sqs_url" {
  value = aws_sqs_queue.instance_orchestrator_event_router_queue.id
}

output "installed_region" {
  value = data.aws_region.current.name
}

output "xosphere_version" {
  value = local.version
}
