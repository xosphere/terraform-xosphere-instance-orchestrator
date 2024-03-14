locals {
  version = "0.26.0"
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

  statemap__group_inspector = "pending,terminated"
  statemap__org_inventory_and_group_inspector = "pending,terminated,stopped"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}