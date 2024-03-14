resource "aws_iam_policy" "run_instances_managed_policy" {
  name        = "xosphere-instance-orchestrator-RunInstances-policy"
  description = "Policy to allow RunInstances and associated API calls"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
%{ if var.enhanced_security_tag_restrictions }
    {
      "Sid": "AllowEc2RunInstances",
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
%{ if var.ec2_ami_arns != "" }
    {
      "Sid": "AllowEc2RunInstancesDefinedAMIs",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "${var.ec2_ami_arns}"
      ]
    },
%{ endif }
    {
      "Sid": "AllowEc2RunInstancesOnXoGroup",
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
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesOnEnabled",
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
          "aws:ResourceTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
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
      "Sid": "AllowEc2RunInstancesOnEnabledInstance",
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
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2RunInstancesXoGroupInstance",
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
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesOnEnabled",
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
        "StringLike": {
          "ec2:CreateAction": "RunInstances",
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnRunInstancesXoGroup",
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
        "StringLike": {
          "ec2:CreateAction": "RunInstances",
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },{
      "Sid": "AllowUseKmsOnAuthorized",
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
%{ if var.enhanced_security_tag_restrictions }
    {
      "Sid": "AllowEc2CreateFleet",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
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
      "Sid": "AllowEc2CreateFleetOnXoGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:ResourceTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateFleetOnEnabled",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "NotResource": [
        "arn:*:ec2:*:*:instance/*",
        "arn:*:ec2:*:*:network-interface/*",
        "arn:*:ec2:*:*:volume/*",
        "arn:*:elastic-inference:*:*:elastic-inference-accelerator/*"
      ],
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
      "Sid": "AllowEc2CreateFleet",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet"
      ],
      "Resource": "*"
    },
%{ endif }
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
      "Sid": "AllowEc2CreateFleetOnEnabledInstance",
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
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowEc2CreateFleetXoGroupInstance",
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
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetOnEnabled",
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
        "StringLike": {
          "ec2:CreateAction": "CreateFleet",
          "aws:RequestTag/xosphere.io/instance-orchestrator/enabled": [
            "*"
          ]
        }
      }
    },
    {
      "Sid": "AllowCreateTagsOnCreateFleetXoGroup",
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
        "StringLike": {
          "ec2:CreateAction": "CreateFleet",
          "aws:RequestTag/xosphere.io/instance-orchestrator/xogroup-name": [
            "*"
          ]
        }
      }
    },{
      "Sid": "AllowUseKmsOnAuthorized",
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
    }
  ]
}
EOF
}
