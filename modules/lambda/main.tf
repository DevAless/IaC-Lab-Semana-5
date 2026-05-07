resource "aws_lambda_function" "upload" {
  function_name    = "${var.project}-${var.env}-upload-lambda"
  role             = var.upload_role_arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 256
  timeout          = 30
  filename         = var.upload_zip_path
  source_code_hash = filebase64sha256(var.upload_zip_path)

  environment {
    variables = {
      S3_BUCKET     = var.s3_bucket_name
      UPLOAD_PREFIX = "uploads/"
      ENV           = var.env
    }
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.sg_upload_lambda_id]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-upload-lambda"
  })
}

resource "aws_lambda_function" "crop" {
  function_name    = "${var.project}-${var.env}-crop-lambda"
  role             = var.crop_role_arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 512
  timeout          = 60
  filename         = var.crop_zip_path
  source_code_hash = filebase64sha256(var.crop_zip_path)

  environment {
    variables = {
      S3_BUCKET        = var.s3_bucket_name
      PROCESSED_PREFIX = "processed/"
      ENV              = var.env
    }
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.sg_crop_lambda_id]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-crop-lambda"
  })
}

resource "aws_lambda_event_source_mapping" "sqs_to_crop" {
  event_source_arn                   = var.sqs_queue_arn
  function_name                      = aws_lambda_function.crop.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.env == "prod" ? 10 : 2
  }
}

resource "aws_lambda_permission" "apigw_upload" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}
