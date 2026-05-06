# modules/sqs/main.tf
# Cola principal + Dead-Letter Queue con política de acceso

# ─── DEAD-LETTER QUEUE ────────────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-${var.env}-image-dlq"
  message_retention_seconds = 1209600 # 14 días (máximo permitido)

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-image-dlq"
  })
}

# ─── COLA PRINCIPAL ───────────────────────────────────────────────────────────
resource "aws_sqs_queue" "main" {
  name                       = "${var.project}-${var.env}-image-queue"
  visibility_timeout_seconds = 360  # 6x el timeout de la Lambda crop (60s)
  message_retention_seconds  = 86400 # 1 día
  receive_wait_time_seconds  = 20   # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3  # Después de 3 fallos → DLQ
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-image-queue"
  })
}

# ─── POLÍTICA: Permite que S3 publique en la cola ─────────────────────────────
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = var.s3_bucket_arn
          }
        }
      }
    ]
  })
}
