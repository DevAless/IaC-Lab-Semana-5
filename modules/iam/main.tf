# ─── POLÍTICA DE CONFIANZA COMÚN PARA LAMBDA ─────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# ROL: upload-lambda-role
# Permisos: logs básicos + VPC + s3:PutObject en uploads/ únicamente
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "upload_lambda" {
  name               = "${var.project}-${var.env}-upload-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = var.tags
}

# Permisos básicos de Lambda (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "upload_basic_execution" {
  role       = aws_iam_role.upload_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permisos para ejecutarse dentro de VPC (crear ENIs)
resource "aws_iam_role_policy_attachment" "upload_vpc_access" {
  role       = aws_iam_role.upload_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Política custom: s3:PutObject SOLO en el prefijo uploads/
resource "aws_iam_role_policy" "upload_s3_put" {
  name = "${var.project}-${var.env}-upload-s3-put"
  role = aws_iam_role.upload_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowPutUploadPrefix"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.s3_bucket_arn}/uploads/*"
      }
    ]
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# ROL: crop-lambda-role
# Permisos: logs + VPC + s3:GetObject(uploads/) + s3:PutObject(processed/)
#           + sqs: ReceiveMessage, DeleteMessage, GetQueueAttributes,
#                  ChangeMessageVisibility
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "crop_lambda" {
  name               = "${var.project}-${var.env}-crop-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "crop_basic_execution" {
  role       = aws_iam_role.crop_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crop_vpc_access" {
  role       = aws_iam_role.crop_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Política custom: S3 + SQS con mínimo privilegio
resource "aws_iam_role_policy" "crop_s3_sqs" {
  name = "${var.project}-${var.env}-crop-s3-sqs"
  role = aws_iam_role.crop_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetObjectUploads"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${var.s3_bucket_arn}/uploads/*"
      },
      {
        Sid    = "AllowPutObjectProcessed"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${var.s3_bucket_arn}/processed/*"
      },
      {
        Sid    = "AllowSQSOperations"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}
