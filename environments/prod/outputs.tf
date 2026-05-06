# environments/prod/outputs.tf

output "api_endpoint"    { value = module.api_gateway.api_endpoint }
output "s3_bucket_name"  { value = module.s3.bucket_name }
output "sqs_queue_url"   { value = module.sqs.queue_url }
output "upload_log_group"{ value = module.observability.upload_log_group_name }
output "dlq_alarm_name"  { value = module.observability.dlq_alarm_name }
