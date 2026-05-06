# ─── UPLOAD LAMBDA ────────────────────────────────────────────────────────────
resource "aws_lambda_function" "upload" {
  function_name = "${var.project}-${var.env}-upload-lambda"
  role          = var.upload_role_arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  memory_size   = 256
  timeout       = 30

  filename         = var.upload_zip_path
  source_code_hash = filebase64sha256(var.upload_zip_path)

  # Variables de entorno tal como especifica el diagrama
  environment {
    variables = {
      S3_BUCKET     = var.s3_bucket_name
      UPLOAD_PREFIX = "uploads/"
      ENV           = var.env
    }
  }

  # Despliegue dentro de la VPC
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.sg_upload_lambda_id]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-upload-lambda"
  })

  depends_on = [var.s3_endpoint_dependency]
}

# ─── CROP LAMBDA ──────────────────────────────────────────────────────────────
resource "aws_lambda_function" "crop" {
  function_name = "${var.project}-${var.env}-crop-lambda"
  role          = var.crop_role_arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  memory_size   = 512  # Más memoria para procesamiento de imagen con sharp
  timeout       = 60

  filename         = var.crop_zip_path
  source_code_hash = filebase64sha256(var.crop_zip_path)

  environment {
    variables = {
      S3_BUCKET        = var.s3_bucket_name
      PROCESSED_PREFIX = "processed/"
      ENV              = var.env
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.sg_crop_lambda_id]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-crop-lambda"
  })

  depends_on = [var.s3_endpoint_dependency]
}

# ─── TRIGGER SQS → CROP LAMBDA (Event Source Mapping) ────────────────────────
resource "aws_lambda_event_source_mapping" "sqs_to_crop" {
  event_source_arn                   = var.sqs_queue_arn
  function_name                      = aws_lambda_function.crop.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10

  # ReportBatchItemFailures: permite que la Lambda reporte fallas por item
  # sin fallar el batch entero → los mensajes fallidos van al DLQ individualmente
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.env == "prod" ? 10 : 2
  }
}

# ─── PERMISO: API Gateway puede invocar upload-lambda ─────────────────────────
resource "aws_lambda_permission" "apigw_upload" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}
