
terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 4.58 added scaling_config on aws_lambda_event_source_mapping.
      version = ">= 4.58"
    }
  }
}
