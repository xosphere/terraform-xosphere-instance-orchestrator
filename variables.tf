# Xosphere Instance Orchestration configuration
variable "customer_id" {

}

variable "tags" {
  description = "Map of tag keys and values to be applied to objects created by this module (where applicable)"
  type = map
  default = {}
}

variable "min_on_demand" {
  description = "Minimum number of On-Demand instances per Auto Scaling Group"
  default = "0"
}

variable "pct_on_demand" {
  description = "Percentage of On-Demand instances per Auto Scaling Group"
  default = "0.0"
}

variable "regions_enabled" {
  description = "Regions enabled for Instance Orchestrator"
  default = ["us-east-1","us-west-2"]
}

variable "enable_cloudwatch" {
  description = "Enable publishing of CloudWatch metrics.  Note, this may result in increased AWS charges"
  default = "false"
}

variable "enable_ecs" {
  description = "Enable processing for ecs cluster. By disabling this the AWS API calls can be reduced."
  default = "true"
}

variable "lambda_archive" {
  description = "Name of the archive file containing the Lamda code"
  default = "./instance-orchestrator-lambda.zip"
}

variable "lambda_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 1024
}

variable "lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 120
}

variable "lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "lambda_cron_schedule" {
  description = "Lambda function schedule cron expression"
  default = "0/2 * * * ? *"
}

variable "terminator_lambda_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "terminator_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "terminator_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "snapshot_creator_cron_schedule" {
  description = "Snapshot creator function schedule cron expression"
  default = "0/15 * * * ? *"
}

variable "group_inspector_cron_schedule" {
  description = "Group Inspector function schedule cron expression"
  default = "0/15 * * * ? *"
}

variable "ami_cleaner_cron_schedule" {
  description = "AMI cleaner function schedule cron expression"
  default = "7 10 * * ? *"
}

variable "io_launcher_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "io_launcher_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "io_launcher_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "io_scheduler_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "io_scheduler_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "io_scheduler_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "io_budget_driver_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "io_budget_driver_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 90
}

variable "io_budget_driver_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "budget_lambda_cron_schedule" {
  description = "budget driver function schedule cron expression"
  default = "0/2 * * * ? *"
}

variable "io_budget_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "io_budget_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "io_budget_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "snapshot_creator_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "snapshot_creator_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 300
}

variable "snapshot_creator_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "ami_cleaner_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "ami_cleaner_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "ami_cleaner_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "dlq_handler_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "dlq_handler_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 120
}

variable "dlq_handler_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "io_bridge_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "io_bridge_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 180
}

variable "io_bridge_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "io_xogroup_enabler_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 256
}

variable "io_xogroup_enabler_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 90
}

variable "io_group_inspector_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "io_group_inspector_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "io_group_inspector_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 300
}

variable "io_xogroup_enabler_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "k8s_vpc_security_group_ids" {
  description = "The security group ids for VPC in Kubernetes cluster"
  type = list
  default = []
}

variable "k8s_vpc_subnet_ids" {
  description = "The subnet ids of VPC in Kubernetes cluster"
  type = list
  default = []
}

variable "daily_budget_grace_period_in_seconds" {
  description = "Grace period in seconds for daily budget enforcement"
  default = 1200
}

variable "monthly_budget_grace_period_in_seconds" {
  description = "Grace period in seconds for monthly budget enforcement"
  default = 36000
}

variable "k8s_drain_timeout_in_mins" {
  description = "Timeout in minutes for K8s node drain request"
  default = 15
}

variable "sns_arn_resource_pattern" {
  description = "ARN pattern to use for IAM privileges for publishing to SNS topics"
  default = "*"
}

variable "passrole_arn_resource_pattern" {
  description = "ARN pattern to use for IAM PassRole for EC2"
  default = "*"
}

variable "enable_auto_support" {
  description = "Enable Auto Support"
  default = 1
}
