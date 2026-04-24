output "sns_topic_arn" {
  description = "ARN of SNS topic for cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "cost_reporter_function_name" {
  description = "Name of cost reporter Lambda function"
  value       = aws_lambda_function.cost_reporter.function_name
}

output "anomaly_detector_function_name" {
  description = "Name of anomaly detector Lambda function"
  value       = aws_lambda_function.anomaly_detector.function_name
}

output "resource_optimizer_function_name" {
  description = "Name of resource optimizer Lambda function"
  value       = aws_lambda_function.resource_optimizer.function_name
}

output "eventbridge_dlq_url" {
  description = "URL of EventBridge dead-letter queue"
  value       = aws_sqs_queue.eventbridge_dlq.id
}

output "deployment_instructions" {
  value = <<-EOT
    Deployment successful! Next steps:
    1. Check ${var.alert_email} for SNS subscription confirmation
    2. Confirm subscription by clicking link in email
    3. Wait for first daily report (runs at 8 AM UTC)
    4. Review CloudWatch Logs for function execution details
  EOT
}
