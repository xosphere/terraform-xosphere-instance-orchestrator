output "event_relay_iam_role_arn" {
  value = aws_iam_role.xosphere_event_relay_iam_role.arn
}

output "event_router_sqs_url" {
  value = aws_sqs_queue.instance_orchestrator_event_router_queue.id
}

output "installed_region" {
  value = data.aws_region.current.name
}

output "xosphere_version" {
  value = local.version
}