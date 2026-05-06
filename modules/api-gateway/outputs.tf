# modules/api-gateway/outputs.tf

output "api_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "api_execution_arn" {
  value = aws_apigatewayv2_api.main.execution_arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.apigw.name
}
