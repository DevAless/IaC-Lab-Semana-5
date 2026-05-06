# modules/observability/outputs.tf

output "upload_log_group_name" {
  value = aws_cloudwatch_log_group.upload_lambda.name
}

output "crop_log_group_name" {
  value = aws_cloudwatch_log_group.crop_lambda.name
}

output "dlq_alarm_name" {
  value = aws_cloudwatch_metric_alarm.dlq_messages.alarm_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.dlq_alarm.arn
}
