resource "aws_s3_bucket" "instance_state_s3_bucket" {
  force_destroy = true
  bucket_prefix = "xosphere-instance-orchestrator"
}

resource "aws_sqs_queue" "instance_orchestrator_launcher_dlq" {
  name = "xosphere-instance-orchestrator-launch-dlq"
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "instance_orchestrator_launcher_queue" {
  name = "xosphere-instance-orchestrator-launch"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.instance_orchestrator_launcher_dlq.arn}\",\"maxReceiveCount\":5}"
  visibility_timeout_seconds = 1020
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_dlq" {
  name = "xosphere-instance-orchestrator-schedule-dlq"
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_queue" {
  name = "xosphere-instance-orchestrator-schedule"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.instance_orchestrator_schedule_dlq.arn}\",\"maxReceiveCount\":5}"
  visibility_timeout_seconds = 1020
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_dlq" {
  name = "xosphere-instance-orchestrator-snapshot-dlq"
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_queue" {
  name = "xosphere-instance-orchestrator-snapshot"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.instance_orchestrator_snapshot_dlq.arn}\",\"maxReceiveCount\":5}"
  visibility_timeout_seconds = 1020
}

resource "aws_sqs_queue" "instance_orchestrator_budget_dlq" {
  name = "xosphere-instance-orchestrator-budget-dlq"
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "instance_orchestrator_budget_queue" {
  name = "xosphere-instance-orchestrator-budget"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.instance_orchestrator_budget_dlq.arn}\",\"maxReceiveCount\":5}"
  visibility_timeout_seconds = 1020
}

//terminator
resource "aws_lambda_function" "xosphere_terminator_lambda_k8s_enabled" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"
  s3_bucket = "xosphere-io-releases"
  s3_key = "terminator-lambda-0.15.0.zip"
  description = "Xosphere Terminator"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
      IO_BRIDGE_NAME = "xosphere-io-bridge"
      K8S_VPC_ENABLED = "true"
    }
  }
  function_name = "xosphere-terminator-lambda"
  handler = "terminator"
  memory_size = "${var.terminator_lambda_memory_size}"
  role = "${aws_iam_role.xosphere_terminator_role.arn}"
  runtime = "go1.x"
  timeout = "${var.terminator_lambda_timeout}"
}

resource "aws_lambda_function" "xosphere_terminator_lambda" {
  count = "${length(var.k8s_vpc_security_group_ids) == 0  || length(var.k8s_vpc_subnet_ids) == 0 ? 1 : 0}"
  s3_bucket = "xosphere-io-releases"
  s3_key = "terminator-lambda-0.15.0.zip"
  description = "Xosphere Terminator"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
      IO_BRIDGE_NAME = "xosphere-io-bridge"
      K8S_VPC_ENABLED = "false"
    }
  }
  function_name = "xosphere-terminator-lambda"
  handler = "terminator"
  memory_size = "${var.terminator_lambda_memory_size}"
  role = "${aws_iam_role.xosphere_terminator_role.arn}"
  runtime = "go1.x"
  timeout = "${var.terminator_lambda_timeout}"
}

resource "aws_lambda_permission" "xosphere_terminator_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "xosphere-terminator-lambda"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.xosphere_terminator_cloudwatch_event_rule.arn}"
  statement_id = "AllowExecutionFromCloudWatch"
}

resource "aws_iam_role_policy" "xosphere_terminator_policy" {
  name = "xosphere-terminator-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeNotificationConfigurations",
        "autoscaling:DetachInstances",
        "ec2:CreateTags",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ecs:DescribeContainerInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeVolumes",
        "ecs:ListClusters",
        "ecs:ListContainerInstances",
        "ecs:UpdateContainerInstancesState",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "iam:CreateServiceLinkedRole",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "sns:Publish",
        "sqs:SendMessage",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
  role = "${aws_iam_role.xosphere_terminator_role.id}"
}

resource "aws_iam_role" "xosphere_terminator_role" {
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
  name = "xosphere-terminator-role"
  path = "/"
}

resource "aws_cloudwatch_log_group" "xosphere_terminator_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-terminator-lambda"
  retention_in_days = "${var.terminator_lambda_log_retention}"
}

resource "aws_cloudwatch_event_rule" "xosphere_terminator_cloudwatch_event_rule" {
  description = "CloudWatch Event trigger for Spot termination notifications for Terminator"
  event_pattern = <<PATTERN
{
  "source": [
    "aws.ec2"
  ],
  "detail-type": [
    "EC2 Spot Instance Interruption Warning"
  ]
}
PATTERN
  name = "xosphere-terminator-cloudwatch-rule"
}

data "aws_lambda_function" "terminator_lambda_function" {
  function_name = "xosphere-terminator-lambda"
  depends_on = [
    "aws_lambda_function.xosphere_terminator_lambda",
    "aws_lambda_function.xosphere_terminator_lambda_k8s_enabled"]
}

resource "aws_cloudwatch_event_target" "xosphere_terminator_cloudwatch_event_target" {
  arn = "${data.aws_lambda_function.terminator_lambda_function.arn}"
  rule = "${aws_cloudwatch_event_rule.xosphere_terminator_cloudwatch_event_rule.name}"
  target_id = "xosphere-terminator"
  depends_on = [
    "data.aws_lambda_function.terminator_lambda_function"]
}

//instance-orchestrator
resource "aws_lambda_function" "xosphere_instance_orchestrator_lambda_k8s_enabled" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"
  s3_bucket = "xosphere-io-releases"
  s3_key = "instance-orchestrator-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator"
  environment {
    variables = {
      REGIONS = "${var.regions_enabled}"
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
      SQS_SCHEDULER_QUEUE = "${aws_sqs_queue.instance_orchestrator_schedule_queue.id}"
      SQS_SNAPSHOT_QUEUE = "${aws_sqs_queue.instance_orchestrator_snapshot_queue.id}"
      IO_BRIDGE_NAME = "xosphere-io-bridge"
      MIN_ON_DEMAND = "${var.min_on_demand}"
      PERCENT_ON_DEMAND = "${var.pct_on_demand}"
      ENABLE_CLOUDWATCH = "${var.enable_cloudwatch}"
      K8S_VPC_ENABLED = "true"
    }
  }
  function_name = "xosphere-instance-orchestrator-lambda"
  handler = "instance-orchestrator"
  memory_size = "${var.lambda_memory_size}"
  role = "${aws_iam_role.xosphere_instance_orchestrator_role.arn}"
  runtime = "go1.x"
  timeout = "${var.lambda_timeout}"
}

resource "aws_lambda_function" "xosphere_instance_orchestrator_lambda" {
  count = "${length(var.k8s_vpc_security_group_ids) == 0  || length(var.k8s_vpc_subnet_ids) == 0 ? 1 : 0}"
  s3_bucket = "xosphere-io-releases"
  s3_key = "instance-orchestrator-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator"
  environment {
    variables = {
      REGIONS = "${var.regions_enabled}"
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
      SQS_SCHEDULER_QUEUE = "${aws_sqs_queue.instance_orchestrator_schedule_queue.id}"
      SQS_SNAPSHOT_QUEUE = "${aws_sqs_queue.instance_orchestrator_snapshot_queue.id}"
      IO_BRIDGE_NAME = "xosphere-io-bridge"
      MIN_ON_DEMAND = "${var.min_on_demand}"
      PERCENT_ON_DEMAND = "${var.pct_on_demand}"
      ENABLE_CLOUDWATCH = "${var.enable_cloudwatch}"
      K8S_VPC_ENABLED = "false"
    }
  }
  function_name = "xosphere-instance-orchestrator-lambda"
  handler = "instance-orchestrator"
  memory_size = "${var.lambda_memory_size}"
  role = "${aws_iam_role.xosphere_instance_orchestrator_role.arn}"
  runtime = "go1.x"
  timeout = "${var.lambda_timeout}"
}

resource "aws_lambda_permission" "xosphere_instance_orchestrator_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "xosphere-instance-orchestrator-lambda"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.xosphere_instance_orchestrator_cloudwatch_event_rule.arn}"
  statement_id = "AllowExecutionFromCloudWatch"
}

resource "aws_iam_role_policy" "xosphere_instance_orchestrator_policy" {
  name = "xosphere-instance-orchestrator-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:AttachInstances",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:BatchPutScheduledUpdateGroupAction",
        "autoscaling:BatchDeleteScheduledAction",
        "autoscaling:DescribeScheduledActions",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeNotificationConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:DetachInstances",
        "autoscaling:UpdateAutoScalingGroup",
        "cloudwatch:PutMetricData",
        "ec2:CreateNetworkInterface",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
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
        "ec2:DescribeVolumes",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ecs:DeregisterContainerInstance",
        "ecs:DescribeContainerInstances",
        "ecs:ListClusters",
        "ecs:ListContainerInstances",
        "ecs:ListTasks",
        "ecs:UpdateContainerInstancesState",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "lambda:InvokeFunction",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetObjectTagging",
        "s3:PutObjectTagging",
        "sns:Publish",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
  role = "${aws_iam_role.xosphere_instance_orchestrator_role.id}"
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
  name = "xosphere-instance-orchestrator-role"
  path = "/"
}

resource "aws_cloudwatch_log_group" "xosphere_instance_orchestrator_cloudwatch_log_group" {
  name = "/aws/lambda/xosphere-instance-orchestrator-lambda"
  retention_in_days = "${var.lambda_log_retention}"
}

resource "aws_cloudwatch_event_rule" "xosphere_instance_orchestrator_cloudwatch_event_rule" {
  name = "xosphere-instance-orchestrator-frequency"
  schedule_expression = "cron(${var.lambda_cron_schedule})"
}

data "aws_lambda_function" "instance_orchestrator_lambda_function" {
  function_name = "xosphere-instance-orchestrator-lambda"
  depends_on = [
    "aws_lambda_function.xosphere_instance_orchestrator_lambda",
    "aws_lambda_function.xosphere_instance_orchestrator_lambda_k8s_enabled"]
}

resource "aws_cloudwatch_event_target" "xosphere_instance_orchestrator_cloudwatch_event_target" {
  arn = "${data.aws_lambda_function.instance_orchestrator_lambda_function.arn}"
  rule = "${aws_cloudwatch_event_rule.xosphere_instance_orchestrator_cloudwatch_event_rule.name}"
  target_id = "xosphere-instance-orchestrator"
  depends_on = [
    "data.aws_lambda_function.instance_orchestrator_lambda_function"]
}

//launcher

resource "aws_lambda_function" "xosphere_instance_orchestrator_launcher_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "launcher-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Launcher"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
    }
  }
  function_name = "xosphere-instance-orchestrator-launcher"
  handler = "launcher"
  memory_size = "${var.io_launcher_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_launcher_lambda_role.arn}"
  runtime = "go1.x"
  timeout = "${var.io_launcher_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_launcher_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn}"
  principal = "sqs.amazonaws.com"
  source_arn = "${aws_sqs_queue.instance_orchestrator_launcher_queue.arn}"
  statement_id = "AllowSQSInvoke"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_launcher_lambda_sqs_trigger" {
  event_source_arn = "${aws_sqs_queue.instance_orchestrator_launcher_queue.arn}"
  function_name = "${aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.arn}"
  batch_size = 1
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
  name = "xosphere-instance-orchestrator-launcher-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_launcher_lambda_policy" {
  name = "xosphere-instance-orchestrator-launcher-policy"
  role = "${aws_iam_role.instance_orchestrator_launcher_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:AssociateAddress",
        "ec2:CreateImage",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeTags",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes",
        "ec2:ModifyInstanceAttribute",
        "ec2:RunInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "sns:Publish",
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_launcher_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.xosphere_instance_orchestrator_launcher_lambda.function_name}"
  retention_in_days = "${var.io_launcher_lambda_log_retention}"
}

//scheduler

resource "aws_lambda_function" "instance_orchestrator_scheduler_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "scheduler-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Scheduler"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_schedule_queue.id}"
    }
  }
  function_name = "xosphere-instance-orchestrator-scheduler"
  handler = "scheduler"
  memory_size = "${var.io_scheduler_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_scheduler_lambda_role.arn}"
  runtime = "go1.x"
  timeout = "${var.io_scheduler_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_scheduler_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_scheduler_lambda.arn}"
  principal = "sqs.amazonaws.com"
  source_arn = "${aws_sqs_queue.instance_orchestrator_schedule_queue.arn}"
  statement_id = "AllowSQSInvoke"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_scheduler_lambda_sqs_trigger" {
  event_source_arn = "${aws_sqs_queue.instance_orchestrator_schedule_queue.arn}"
  function_name = "${aws_lambda_function.instance_orchestrator_scheduler_lambda.arn}"
  batch_size = 1
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
  name = "xosphere-instance-orchestrator-scheduler-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_scheduler_lambda_policy" {
  name = "xosphere-instance-orchestrator-scheduler-policy"
  role = "${aws_iam_role.instance_orchestrator_scheduler_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:DeleteTags",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_scheduler_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_scheduler_lambda.function_name}"
  retention_in_days = "${var.io_scheduler_lambda_log_retention}"
}


//budget Driver

resource "aws_lambda_function" "instance_orchestrator_budget_driver_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "budget-driver-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Budget Driver"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_BUDGET_QUEUE = "${aws_sqs_queue.instance_orchestrator_budget_queue.id}"
      SQS_LAUNCHER_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_queue.id}"
      REGIONS = "${var.regions_enabled}"
      DAILY_BUFFER_SECONDS = "${var.daily_budget_grace_period_in_seconds}"
      MONTHLY_BUFFER_SECONDS = "${var.monthly_budget_grace_period_in_seconds}"
    }
  }
  function_name = "xosphere-instance-orchestrator-budget-driver"
  handler = "budget-driver"
  memory_size = "${var.io_budget_driver_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_budget_driver_lambda_role.arn}"
  runtime = "go1.x"
  timeout = "${var.io_budget_driver_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_budget_driver_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_budget_driver_lambda.arn}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.instance_orchestrator_budget_driver_cloudwatch_event_rule.arn}"
  statement_id = "AllowExecutionFromCloudWatch"
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
  name = "xosphere-instance-orchestrator-budget-driver-lambda-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_budget_driver_lambda_policy" {
  name = "xosphere-instance-orchestrator-budget-driver-lambda-policy"
  role = "${aws_iam_role.instance_orchestrator_budget_driver_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeTags",
        "autoscaling:UpdateAutoScalingGroup",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole",
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:PutLogEvents",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_budget_driver_cloudwatch_event_rule" {
  name = "xosphere-instance-orchestrator-budget-schedule"
  schedule_expression = "cron(${var.budget_lambda_cron_schedule})"
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_budget_driver_cloudwatch_event_target" {
  arn = "${aws_lambda_function.instance_orchestrator_budget_driver_lambda.arn}"
  rule = "${aws_cloudwatch_event_rule.instance_orchestrator_budget_driver_cloudwatch_event_rule.name}"
  target_id = "xosphere-io-budget-driver"
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_budget_driver_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_budget_driver_lambda.function_name}"
  retention_in_days = "${var.io_budget_driver_lambda_log_retention}"
}

// budget processor

resource "aws_lambda_function" "instance_orchestrator_budget_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "budget-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Budget"
  environment {
    variables = {
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_budget_queue.id}"
    }
  }
  function_name = "xosphere-instance-orchestrator-budget"
  handler = "budget"
  memory_size = "${var.io_budget_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_budget_lambda_role.arn}"
  runtime = "go1.x"
  timeout = "${var.io_budget_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_budget_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_budget_lambda.arn}"
  principal = "sqs.amazonaws.com"
  source_arn = "${aws_sqs_queue.instance_orchestrator_budget_queue.arn}"
  statement_id = "AllowSQSInvoke"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_budget_lambda_sqs_trigger" {
  event_source_arn = "${aws_sqs_queue.instance_orchestrator_budget_queue.arn}"
  function_name = "${aws_lambda_function.instance_orchestrator_budget_lambda.arn}"
  batch_size = 1
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
  name = "xosphere-instance-orchestrator-budget-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_budget_lambda_policy" {
  name = "xosphere-instance-orchestrator-budget-policy"
  role = "${aws_iam_role.instance_orchestrator_budget_lambda_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:DescribeInstanceStatus",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_budget_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_budget_lambda.function_name}"
  retention_in_days = "${var.io_budget_lambda_log_retention}"
}

//snapshot

resource "aws_lambda_function" "instance_orchestrator_snapshot_creator_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "snapshot-creator-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Snapshot Creator"
  environment {
    variables = {
      REGIONS = "${var.regions_enabled}"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
    }
  }
  function_name = "xosphere-instance-orchestrator-snapshot-creator"
  handler = "snapshot-creator"
  memory_size = "${var.snapshot_creator_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_snapshot_creator_role.arn}"
  runtime = "go1.x"
  timeout = "${var.snapshot_creator_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_snapshot_creator_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.instance_orchestrator_snapshot_creator_cloudwatch_event_rule.arn}"
  statement_id = "AllowExecutionFromCloudWatch"
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_snapshot_creator_cloudwatch_event_rule" {
  name = "xosphere-io-snapshot-creator-schedule"
  schedule_expression = "cron(${var.snapshot_creator_cron_schedule})"
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_snapshot_creator_cloudwatch_event_target" {
  arn = "${aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn}"
  rule = "${aws_cloudwatch_event_rule.instance_orchestrator_snapshot_creator_cloudwatch_event_rule.name}"
  target_id = "xosphere-io-snapshot-creator"
}

resource "aws_lambda_permission" "instance_orchestrator_snapshot_creator_sqs_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn}"
  principal = "sqs.amazonaws.com"
  source_arn = "${aws_sqs_queue.instance_orchestrator_snapshot_queue.arn}"
  statement_id = "AllowSQSInvoke"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_snapshot_creator_lambda_sqs_trigger" {
  event_source_arn = "${aws_sqs_queue.instance_orchestrator_snapshot_queue.arn}"
  function_name = "${aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.arn}"
  batch_size = 1
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
  name = "xosphere-instance-orchestrator-snapshot-creator-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_snapshot_creator_policy" {
  name = "xosphere-instance-orchestrator-snapshot-creator-policy"
  role = "${aws_iam_role.instance_orchestrator_snapshot_creator_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:DeleteSnapshot",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "sns:Publish",
        "sns:Subscribe",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_snapshot_creator_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_snapshot_creator_lambda.function_name}"
  retention_in_days = "${var.snapshot_creator_lambda_log_retention}"
}

//AMI cleaner

resource "aws_lambda_function" "instance_orchestrator_ami_cleaner_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "ami-cleaner-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator AMI Cleaner"
  environment {
    variables = {
      REGIONS = "${var.regions_enabled}"
    }
  }
  function_name = "xosphere-instance-orchestrator-ami-cleaner"
  handler = "ami-cleaner"
  memory_size = "${var.ami_cleaner_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_ami_cleaner_role.arn}"
  runtime = "go1.x"
  timeout = "${var.ami_cleaner_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_ami_cleaner_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_ami_cleaner_lambda.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.instance_orchestrator_ami_cleaner_cloudwatch_event_rule.arn}"
  statement_id = "AllowExecutionFromCloudWatch"
}

resource "aws_cloudwatch_event_rule" "instance_orchestrator_ami_cleaner_cloudwatch_event_rule" {
  name = "xosphere-io-ami-cleaner-schedule"
  schedule_expression = "cron(${var.ami_cleaner_cron_schedule})"
}

resource "aws_cloudwatch_event_target" "instance_orchestrator_ami_cleaner_cloudwatch_event_target" {
  arn = "${aws_lambda_function.instance_orchestrator_ami_cleaner_lambda.arn}"
  rule = "${aws_cloudwatch_event_rule.instance_orchestrator_ami_cleaner_cloudwatch_event_rule.name}"
  target_id = "xosphere-io-ami-cleaner"
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
  name = "xosphere-instance-orchestrator-ami-cleaner-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_ami_cleaner_policy" {
  name = "xosphere-instance-orchestrator-ami-cleaner-policy"
  role = "${aws_iam_role.instance_orchestrator_ami_cleaner_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DeregisterImage",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_ami_cleaner_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_ami_cleaner_lambda.function_name}"
  retention_in_days = "${var.ami_cleaner_lambda_log_retention}"
}

//DLQ handler

resource "aws_lambda_function" "instance_orchestrator_dlq_handler_lambda" {
  s3_bucket = "xosphere-io-releases"
  s3_key = "dlq-handler-lambda-0.15.0.zip"
  description = "Xosphere Instance Orchestrator Dead-Letter Queue Handler"
  environment {
    variables = {
      API_TOKEN = "${var.api_token}"
      ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
      INSTANCE_STATE_S3_BUCKET = "${aws_s3_bucket.instance_state_s3_bucket.id}"
      SQS_QUEUE = "${aws_sqs_queue.instance_orchestrator_schedule_queue.id}"
      DEAD_LETTER_QUEUE = "${aws_sqs_queue.instance_orchestrator_launcher_dlq.id}"
    }
  }
  function_name = "xosphere-instance-orchestrator-dlq-handler"
  handler = "dlq-handler"
  memory_size = "${var.dlq_handler_memory_size}"
  role = "${aws_iam_role.instance_orchestrator_dlq_handler_role.arn}"
  runtime = "go1.x"
  timeout = "${var.dlq_handler_lambda_timeout}"
}

resource "aws_lambda_permission" "instance_orchestrator_dlq_handler_lambda_permission" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.instance_orchestrator_dlq_handler_lambda.arn}"
  principal = "sqs.amazonaws.com"
  source_arn = "${aws_sqs_queue.instance_orchestrator_launcher_dlq.arn}"
  statement_id = "AllowSQSInvoke"
}

resource "aws_lambda_event_source_mapping" "instance_orchestrator_dlq_handler_sqs_trigger" {
  event_source_arn = "${aws_sqs_queue.instance_orchestrator_launcher_dlq.arn}"
  function_name = "${aws_lambda_function.instance_orchestrator_dlq_handler_lambda.arn}"
  batch_size = 1
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
  name = "xosphere-instance-orchestrator-dql-handler-role"
  path = "/"
}

resource "aws_iam_role_policy" "instance_orchestrator_dlq_handler_policy" {
  name = "xosphere-instance-orchestrator-dlq-handler-policy"
  role = "${aws_iam_role.instance_orchestrator_dlq_handler_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "iam:CreateServiceLinkedRole",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "instance_orchestrator_dlq_handler_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.instance_orchestrator_dlq_handler_lambda.function_name}"
  retention_in_days = "${var.dlq_handler_lambda_log_retention}"
}

//IO Bridge

resource "aws_lambda_function" "xosphere_io_bridge_lambda" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"

  s3_bucket = "xosphere-io-releases"
  s3_key = "iobridge-lambda-0.15.0.zip"
  description = "Xosphere IO-Bridge"
  environment {
    variables = {
      PORT = "31716"
    }
  }
  function_name = "xosphere-io-bridge"
  handler = "iobridge"
  memory_size = "${var.io_bridge_memory_size}"
  role = "${aws_iam_role.io_bridge_lambda_role[count.index].arn}"
  runtime = "go1.x"
  vpc_config {
    security_group_ids = var.k8s_vpc_security_group_ids
    subnet_ids = var.k8s_vpc_subnet_ids
  }
  timeout = "${var.io_bridge_lambda_timeout}"
}

resource "aws_lambda_permission" "xosphere_io_bridge_permission" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"

  action = "lambda:InvokeFunction"
  function_name = "xosphere-instance-orchestrator-lambda"
  principal = "lambda.amazonaws.com"
  source_arn = "${data.aws_lambda_function.instance_orchestrator_lambda_function.arn}"
  statement_id = "AllowExecutionFromLambda"
}

resource "aws_iam_role" "io_bridge_lambda_role" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"

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
  name = "xosphere-iobridge-lambda-role"
  path = "/"
}

resource "aws_iam_role_policy" "io_bridge_lambda_policy" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"

  name = "xosphere-iobridge-lambda-policy"
  role = "${aws_iam_role.io_bridge_lambda_role[count.index].id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "iam:PassRole",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "io_bridge_cloudwatch_log_group" {
  count = "${length(var.k8s_vpc_security_group_ids) > 0  && length(var.k8s_vpc_subnet_ids) > 0 ? 1 : 0}"

  name = "/aws/lambda/${aws_lambda_function.xosphere_io_bridge_lambda[count.index].function_name}"
  retention_in_days = "${var.io_bridge_lambda_log_retention}"
}