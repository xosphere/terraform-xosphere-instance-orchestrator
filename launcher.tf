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
      TERRAFORMER_LAMBDA_NAME = var.terraform_version != "" ? aws_lambda_function.instance_orchestrator_terraformer_lambda[0].function_name : ""
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
  managed_policy_arns = [ aws_iam_policy.run_instances_managed_policy.arn ]
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
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
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
      "Sid": "AllowEc2CreateImageWithOnEnabledTagImageSnapshot",
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
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateImageWithXoGroupTagImageSnapshot",
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
      "Sid": "AllowEc2RegisterImageWithXoGroupTagSnapshot",
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
    },{
      "Sid": "AllowEc2CreateSnapshotSnapshotEnabled",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateSnapshotSnapshotXoGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot"
      ],
      "Resource": [
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnNewSnapshots",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": [
        "arn:*:ec2:*::image/*",
        "arn:*:ec2:*::snapshot/*"
      ],
      "Condition": {
        "StringLike": {
          "ec2:CreateAction": [
            "CreateImage"
          ],
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": "*"
        }
      }
    },
%{ if var.enhanced_security_managed_resources }
    {
      "Sid": "AllowEc2DeregisterImageOnEnabled",
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
      "Sid": "AllowEc2DeregisterImageXoGroup",
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
      "Sid": "AllowEc2CreateTagsOnEnabled",
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
      "Sid": "AllowEc2CreateTagsXoGroup",
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
      "Sid": "AllowEc2OperationsOnEnabledAsgs",
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
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2OperationsOnXogroups",
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
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
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

resource "aws_iam_role_policy" "instance_orchestrator_launcher_lambda_policy_additional" {
  name = "xosphere-instance-orchestrator-launcher-policy-additional"
  role = aws_iam_role.instance_orchestrator_launcher_lambda_role.id
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