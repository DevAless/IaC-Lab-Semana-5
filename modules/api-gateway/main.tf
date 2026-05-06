# modules/api-gateway/main.tf
# HTTP API v2 con ruta POST /upload, TLS 1.2+, throttling y logs

# ─── HTTP API (v2) ────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-${var.env}-api"
  protocol_type = "HTTP"
  description   = "Image Processor API — ${var.env}"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = var.tags
}

# ─── LOG GROUP PARA ACCESS LOGS ───────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${var.project}-${var.env}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ─── STAGE (auto-deploy habilitado) ───────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Throttling: 10,000 RPS con burst de 5,000
  default_route_settings {
    throttling_burst_limit = 5000
    throttling_rate_limit  = var.throttling_rate_limit
    logging_level          = "INFO"
    data_trace_enabled     = false # Solo en dev; caro en prod
    detailed_metrics_enabled = true
  }

  # Access logs en formato JSON hacia CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
      userAgent      = "$context.identity.userAgent"
      requestTime    = "$context.requestTime"
      integrationLatency = "$context.integrationLatency"
    })
  }

  tags = var.tags
}

# ─── INTEGRACIÓN CON UPLOAD LAMBDA (Lambda Proxy, Payload 2.0) ───────────────
resource "aws_apigatewayv2_integration" "upload_lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.upload_lambda_invoke_arn
  payload_format_version = "2.0"  # Payload format 2.0 como indica el diagrama

  # Timeout máximo para HTTP API: 30s (igual al timeout de la Lambda)
  timeout_milliseconds = 29000
}

# ─── RUTA: POST /upload ───────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.upload_lambda.id}"
}

# ─── PERMISO PARA CLOUDWATCH LOGS ────────────────────────────────────────────
resource "aws_iam_role" "apigw_logs" {
  name = "${var.project}-${var.env}-apigw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "apigw_logs" {
  role       = aws_iam_role.apigw_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigw_logs.arn
}
