# Xosphere Instance Orchestration configuration
variable "customer_id" {}

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
  default = 115
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
  default = 900
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

variable "event_router_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "event_router_enhancer_lambda_log_retention" {
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

variable "k8s_pod_eviction_grace_period" {
  description = "Grace period (in seconds) for pods to complete eviction before being terminated when draining. A value of -1 (the default) means use the cconfiguration of the pod (which defaults to 30 seconds, unless overridden)."
  default = -1
}

variable "sns_arn_resource_pattern" {
  description = "ARN pattern to use for IAM privileges for publishing to SNS topics"
  default = "*"
}

variable "passrole_arn_resource_pattern" {
  description = "ARN pattern to use for IAM PassRole for EC2"
  default = "*"
}

variable "enable_code_deploy_integration" {
  type = bool
  description = "If CodeDeploy Integration is enabled"
  default = true
}

variable "codedeploy_passrole_arn_resource_pattern" {
  description = "ARN pattern to use for IAM PassRole for EC2"
  default = "*"
}

variable "enable_auto_support" {
  description = "Enable Auto Support"
  default = 1
}

variable "terraform_version" {
  description = "The version of Terraform"
  default = ""
}

variable "terraform_aws_provider_version" {
  description = "The version of Terraform AWS Provider"
  default = ""
}

variable "terraform_backend_aws_region" {
  description = "The AWS region for Terraform backend"
  default = ""
}

variable "terraform_backend_s3_bucket" {
  description = "The S3 bucket for Terraform backend"
  default = ""
}

variable "terraform_backend_s3_key" {
  description = "The S3 key for Terraform backend"
  default = ""
}

variable "terraform_backend_dynamodb_table" {
  description = "The dynamoDB table name for Terraform backend"
  default = ""
}

variable "terraform_backend_assume_role_arn" {
  description = "Optional role ARN to assume for Terraform backend operations"
  default = ""
}

variable "terraform_backend_assume_role_external_id" {
  description = "Optional external ID for Terraform backend assume role"
  default = ""
}

variable "terraform_backend_assume_role_session_name" {
  description = "Optional session name for Terraform backend assume role"
  default = "xosphere-terraformer"
}

variable "terraform_backend_use_lockfile" {
  description = "If set to \"true\", use S3 native lock file for Terraform state locking instead of DynamoDB."
  default = ""
}

variable "terraformer_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 1024
}

variable "terraformer_ephemeral_storage" {
  description = "Ephemeral storage size allocated to Lambda"
  default = 2048
}

variable "terraformer_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 300
}

variable "terraformer_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "attacher_memory_size" {
  description = "Memory size allocated to Lambda"
  default = 128
}

variable "attacher_lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 900
}

variable "attacher_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "xo_account_id" {
  default = "143723790106"
}

variable "endpoint_url" {
  default = "https://portal-api.xosphere.io/v1"
}

variable "enhanced_security_tag_restrictions" {
  type = bool
  default = false
}

variable "enhanced_security_managed_resources" {
  type = bool
  default = false
}

variable "enhanced_security_use_cmk" {
  type = bool
  default = false
}

variable "create_logging_buckets" {
  type = bool
  default = false
}

variable "management_account_data_bucket" {
  default = ""
}
  
variable "management_account_region" {
  default = ""
}

variable "management_aws_account_id" {
  default = ""
}

variable "reserved_instances_regional_buffer" {
  default = ""
  description = "Reserved Instances Regional buffer (Overrides Org level setting)"
}

variable "reserved_instances_az_buffer" {
  default = ""
  description = "Reserved Instances AZ buffer (Overrides Org level setting)"
}

variable "ec2_instance_savings_plan_buffer" {
  default = ""
  description = "Ec2 Instance Savings Plan buffer (Overrides Org level setting)"
}

variable "compute_savings_plan_buffer" {
  default = ""
  description = "Compute Savings Plan buffer (Overrides Org level setting)"
}

variable "ignore_lb_health_check" {
  description = "Ignore load balancer health check during replacement. Default as false."
  type = bool
  default = false
}





































## for internal use only
variable "logging_bucket_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "state_bucket_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "ami_cleaner_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "budget_driver_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "budget_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "dlq_handler_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "group_inspector_schedule_cloudwatch_event_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "group_inspector_sqs_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "launcher_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "scheduler_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "scheduler_cwe_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "snapshot_creator_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "snapshot_creator_sqs_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "event_router_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "event_router_enhancer_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "io_bridge_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "orchestrator_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "instance_orchestrator_terraformer_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "instance_orchestrator_attacher_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "secretsmanager_arn_override" {
  description = "An explicit name to use"
  default = null
}

variable "xogroup_enabler_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}

variable "xosphere_terminator_sqs_lambda_permission_name_override" {
  description = "An explicit name to use"
  default = null
}
