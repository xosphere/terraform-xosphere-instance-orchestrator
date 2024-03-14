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
      ENABLE_ECS = var.enable_ecs
      IO_BRIDGE_NAME = local.has_k8s_vpc_config ? aws_lambda_function.xosphere_io_bridge_lambda[0].id : "xosphere-io-bridge"
      ATTACHER_NAME = aws_lambda_function.instance_orchestrator_attacher_lambda.function_name
      K8S_VPC_ENABLED = local.has_k8s_vpc_config_string
      K8S_DRAIN_TIMEOUT_IN_MINS = var.k8s_drain_timeout_in_mins
      RESERVED_INSTANCES_REGIONAL_BUFFER = var.reserved_instances_regional_buffer
      RESERVED_INSTANCES_AZ_BUFFER = var.reserved_instances_az_buffer
      EC2_INSTANCE_SAVINGS_PLAN_BUFFER = var.ec2_instance_savings_plan_buffer
      COMPUTE_SAVINGS_PLAN_BUFFER = var.compute_savings_plan_buffer
      ORGANIZATION_DATA_S3_BUCKET = local.organization_management_account_enabled ? var.management_account_data_bucket : null
      ORGANIZATION_REGION = local.organization_management_account_enabled ? var.management_account_region : null
      ENABLE_CODEDEPLOY = var.enable_code_deploy_integration
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
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn, aws_iam_policy.create_fleet_managed_policy.arn ]
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
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeScheduledActions",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeLifecycleHooks",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLoadBalancers",
        "autoscaling:DescribeLoadBalancerTargetGroups",
        "autoscaling:DescribeNotificationConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:DescribePolicies",
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
        "ec2:DescribeVolumes",
        "ec2:GetSpotPlacementScores",
        "ecs:ListClusters",
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
      "Sid": "AllowAutoScalingOperationsOnEnabledAsgs",
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
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "arn:*:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/*",
      "Condition": {
        "StringEquals": {"autoscaling:ResourceTag/xosphere.io/instance-orchestrator/enabled": "true"}
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
      "Sid": "AllowEc2OperationsOnEnabledAsgs",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": ["*"]}
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroups",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteTags",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:TerminateInstances"
	  ],
      "Resource": "*",
      "Condition": {
        "StringLike": {"aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": ["*"]}
      }
    },
    {
      "Sid": "AllowEcsReadOperations",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeContainerInstances",
        "ecs:ListTasks"
	  ],
      "Resource": "arn:*:ecs:*:*:container-instance/*"
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
        "arn:aws:s3:::xosphere-*"
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
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImage",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImage",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*::image/*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageOnEnabledInstance",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageXoGroupInstance",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateImage"
      ],
      "Resource": "arn:*:ec2:*:*:instance/*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2CreateTagsOnEnabled",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
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
      "Sid": "AllowEc2CreateTagsOnXogroups",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
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
      "Sid": "AllowEcsUpdateOperations",
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateContainerInstancesState" %{ if false } # should use ResourceTag 'authorized', but no Condition Key currently available in IAM %{ endif }
	  ],
      "Resource": "arn:*:ecs:*:*:container-instance/*"
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
      "Sid": "AllowAutoScalingOperationsOnEksNodeGroups",
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