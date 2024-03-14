resource "aws_sqs_queue" "instance_orchestrator_launcher_dlq" {
  name = "xosphere-instance-orchestrator-launch-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_launcher_queue" {
  name = "xosphere-instance-orchestrator-launch"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_launcher_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_dlq" {
  name = "xosphere-instance-orchestrator-event-router-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_queue" {
  name = "xosphere-instance-orchestrator-event-router"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_event_router_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_enhancer_dlq" {
  name = "xosphere-instance-orchestrator-event-router-enhancer-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_event_router_enhancer_queue" {
  name = "xosphere-instance-orchestrator-event-router-enhancer"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_event_router_enhancer_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_dlq" {
  name = "xosphere-instance-orchestrator-schedule-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_schedule_queue" {
  name = "xosphere-instance-orchestrator-schedule"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_schedule_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_dlq" {
  name = "xosphere-instance-orchestrator-snapshot-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_snapshot_queue" {
  name = "xosphere-instance-orchestrator-snapshot"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_snapshot_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_budget_dlq" {
  name = "xosphere-instance-orchestrator-budget-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_budget_queue" {
  name = "xosphere-instance-orchestrator-budget"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_budget_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_group_inspector_dlq" {
  name = "xosphere-instance-orchestrator-group-inspector-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_group_inspector_queue" {
  name = "xosphere-instance-orchestrator-group-inspector"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_group_inspector_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_scheduler_cloudwatch_event_dlq" {
  name = "xosphere-instance-orchestrator-schedule-cwe-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_scheduler_cloudwatch_event_queue" {
  name = "xosphere-instance-orchestrator-schedule-cwe"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_scheduler_cloudwatch_event_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "xosphere_terminator_dlq" {
  name = "xosphere-instance-orchestrator-terminator-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "xosphere_terminator_queue" {
  name = "xosphere-instance-orchestrator-terminator"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.xosphere_terminator_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_xogroup_enabler_dlq" {
  name = "xosphere-instance-orchestrator-xogroup-enabler-dlq"
  visibility_timeout_seconds = 300
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}

resource "aws_sqs_queue" "instance_orchestrator_xogroup_enabler_queue" {
  name = "xosphere-instance-orchestrator-xogroup-enabler"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.instance_orchestrator_xogroup_enabler_dlq.arn
    maxReceiveCount = 5
  })
  visibility_timeout_seconds = 1020
  kms_master_key_id = var.enhanced_security_use_cmk ? aws_kms_key.xosphere_kms_key[0].arn : "alias/aws/sqs"
  tags = var.tags
}