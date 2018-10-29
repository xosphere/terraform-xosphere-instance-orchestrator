# Xosphere Instance Orchestration configuration
variable "api_token" {
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
  default = "us-east-1,us-west-2"
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
  default = 256
}

variable "lambda_timeout" {
  description = "Lambda function execution timeout"
  default = 120
}

variable "lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 7
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
  default = 60
}

variable "terminator_lambda_log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}
