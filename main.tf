resource "aws_lambda_function" "xosphere_terminator_lambda" {
	s3_bucket = "xosphere-io-releases"
	s3_key = "terminator-lambda-0.2.0.zip"
	description = "Xosphere Terminator"
	function_name = "xosphere-terminator-lambda"
	handler = "terminator"
	memory_size = "${var.terminator_lambda_memory_size}"
	role = "${aws_iam_role.xosphere_terminator_role.arn}"
 	runtime = "go1.x"
	timeout = "${var.terminator_lambda_timeout}"
}

resource "aws_lambda_permission" "xosphere_terminator_lambda_permission" {
	action = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.xosphere_terminator_lambda.function_name}"
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
              	"ec2:DescribeInstances",
              	"ecs:DescribeContainerInstances",
              	"ecs:ListClusters",
              	"ecs:ListContainerInstances",
              	"ecs:UpdateContainerInstancesState",
              	"sns:Publish"	
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
	name = "/aws/lambda/${aws_lambda_function.xosphere_terminator_lambda.function_name}"
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

resource "aws_cloudwatch_event_target" "xosphere_terminator_cloudwatch_event_target" {
	arn = "${aws_lambda_function.xosphere_terminator_lambda.arn}"
	rule = "${aws_cloudwatch_event_rule.xosphere_terminator_cloudwatch_event_rule.name}"
	target_id = "xosphere-terminator"
}

resource "aws_lambda_function" "xosphere_instance_orchestrator_lambda" {
	s3_bucket = "xosphere-io-releases"
	s3_key = "instance-orchestrator-lambda-0.9.2.zip"
	description = "Xosphere Instance Orchestrator"
	environment {
    		variables = {
				REGIONS = "${var.regions_enabled}"
				API_TOKEN = "${var.api_token}"
				ENDPOINT_URL = "https://portal-api.xosphere.io/v1"
	      		MIN_ON_DEMAND = "${var.min_on_demand}"
	      		PERCENT_ON_DEMAND = "${var.pct_on_demand}"
				ENABLE_CLOUDWATCH = "${var.enable_cloudwatch}"
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
	function_name = "${aws_lambda_function.xosphere_instance_orchestrator_lambda.function_name}"
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
				"autoscaling:DescribeAutoScalingGroups",
				"autoscaling:DescribeLaunchConfigurations",
				"autoscaling:DescribeNotificationConfigurations",
				"autoscaling:AttachInstances",
				"autoscaling:DetachInstances",
				"autoscaling:DescribeTags",
				"autoscaling:UpdateAutoScalingGroup",
				"cloudwatch:PutMetricData",
				"ec2:CreateTags",
				"ec2:DescribeAccountAttributes",
				"ec2:DescribeInstances",
				"ec2:DescribeRegions",
				"ec2:DescribeReservedInstances",
				"ec2:DescribeSpotInstanceRequests",
				"ec2:DescribeSpotPriceHistory",
				"ec2:RequestSpotInstances",
				"ec2:TerminateInstances",
				"iam:CreateServiceLinkedRole",
				"iam:PassRole",
				"logs:CreateLogGroup",
				"logs:CreateLogStream",
				"logs:PutLogEvents",
				"sns:Publish",
				"s3:GetObject"
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
	name = "/aws/lambda/${aws_lambda_function.xosphere_instance_orchestrator_lambda.function_name}"
	retention_in_days = "${var.lambda_log_retention}"
}

resource "aws_cloudwatch_event_rule" "xosphere_instance_orchestrator_cloudwatch_event_rule" {
	name = "xosphere-instance-orchestrator-frequency"
	schedule_expression = "cron(${var.lambda_cron_schedule})"
}

resource "aws_cloudwatch_event_target" "xosphere_instance_orchestrator_cloudwatch_event_target" {
	arn = "${aws_lambda_function.xosphere_instance_orchestrator_lambda.arn}"
	rule = "${aws_cloudwatch_event_rule.xosphere_instance_orchestrator_cloudwatch_event_rule.name}"
	target_id = "xosphere-instance-orchestrator"
}

