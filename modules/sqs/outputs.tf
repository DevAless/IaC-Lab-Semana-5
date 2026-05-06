# modules/sqs/outputs.tf

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}

output "queue_url" {
  value = aws_sqs_queue.main.url
}

output "queue_name" {
  value = aws_sqs_queue.main.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "sqs_policy" {
  value = aws_sqs_queue_policy.allow_s3
}
