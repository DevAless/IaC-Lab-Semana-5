resource "aws_s3_bucket" "images" {
  bucket = var.bucket_name

  # Forzar borrado del bucket aunque tenga objetos (útil para destroy en dev)
  force_destroy = var.env != "prod"

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

# ─── CIFRADO AES-256 (SSE-S3) ────────────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ─── VERSIONAMIENTO ───────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─── BLOQUEO TOTAL DE ACCESO PÚBLICO ─────────────────────────────────────────
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── LIFECYCLE RULES ──────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  # uploads/ → expira en 30 días
  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter {
      prefix = "uploads/"
    }

    expiration {
      days = var.uploads_expiration_days
    }

    # Limpiar también versiones antiguas
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # processed/ → expira en 90 días
  rule {
    id     = "expire-processed"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = var.processed_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 14
    }
  }
}

# ─── CORS (necesario para uploads desde browser) ──────────────────────────────
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ─── NOTIFICACIÓN S3 → SQS (ObjectCreated en uploads/) ───────────────────────
resource "aws_s3_bucket_notification" "to_sqs" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn     = var.sqs_queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
    # Solo archivos de imagen permitidos
    filter_suffix = "" # Se valida en Lambda; S3 no soporta múltiples sufijos nativamente
  }

  depends_on = [var.sqs_policy_dependency]
}

# ─── POLÍTICA DEL BUCKET ──────────────────────────────────────────────────────
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Forzar HTTPS (denegar HTTP)
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "${aws_s3_bucket.images.arn}",
          "${aws_s3_bucket.images.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      # Permitir notificaciones S3 hacia SQS
      {
        Sid    = "AllowS3ToSQS"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "s3:GetBucketNotification"
        Resource = aws_s3_bucket.images.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.images]
}
