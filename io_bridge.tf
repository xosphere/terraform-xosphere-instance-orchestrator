resource "aws_lambda_function" "xosphere_io_bridge_lambda" {
  count = local.has_k8s_vpc_config ? 1 : 0

  s3_bucket = local.s3_bucket
  s3_key = "iobridge-lambda-${local.version}.zip"
  description = "Xosphere Io-Bridge"
  environment {
    variables = {
      PORT = "31716"
    }
  }
  function_name = "xosphere-io-bridge"
  handler = "bootstrap"
  memory_size = var.io_bridge_memory_size
  role = aws_iam_role.io_bridge_lambda_role[count.index].arn
  runtime = "provided.al2"
  architectures = [ "arm64" ]
  vpc_config {
    security_group_ids = var.k8s_vpc_security_group_ids
    subnet_ids = var.k8s_vpc_subnet_ids
  }
  timeout = var.io_bridge_lambda_timeout
  tags = var.tags
  depends_on = [ aws_cloudwatch_log_group.io_bridge_cloudwatch_log_group ]
}

resource "aws_iam_role" "io_bridge_lambda_role" {
  count = local.has_k8s_vpc_config ? 1 : 0

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
  managed_policy_arns = [ ]
  name = "xosphere-iobridge-lambda-role"
  path = "/"
  tags = var.tags
}

resource "aws_iam_role_policy" "io_bridge_lambda_policy" {
  count = local.has_k8s_vpc_config ? 1 : 0

  name = "xosphere-iobridge-lambda-policy"
  role = aws_iam_role.io_bridge_lambda_role[count.index].id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces"
       ],
      "Resource": "*"
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
      "Sid": "AllowLambdaVpcExecution",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses"
      ],
      "Resource": [
        "*"
      ],
      "Condition": {
        "ForAllValues:StringEquals": {
          "ec2:SubnetID": [ "${join("\",\"", var.k8s_vpc_subnet_ids)}" ],
          "ec2:SecurityGroupID": [ "${join("\",\"", var.k8s_vpc_security_group_ids)}" ]
        }
      }
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "xosphere_io_bridge_permission" {
  count = local.has_k8s_vpc_config ? 1 : 0

  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xosphere_io_bridge_lambda[0].arn
  principal = "lambda.amazonaws.com"
  source_arn = aws_lambda_function.xosphere_instance_orchestrator_lambda.arn
  statement_id = var.io_bridge_permission_name_override == null ? "AllowExecutionFromLambda" : var.io_bridge_permission_name_override
}

resource "aws_cloudwatch_log_group" "io_bridge_cloudwatch_log_group" {
  count = local.has_k8s_vpc_config ? 1 : 0

  name = "/aws/lambda/xosphere-io-bridge"
  retention_in_days = var.io_bridge_lambda_log_retention
  tags = var.tags
}

