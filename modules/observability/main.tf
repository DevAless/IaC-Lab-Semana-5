# ─── LOG GROUP: upload-lambda ─────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "upload_lambda" {
  name              = "/aws/lambda/${var.project}-${var.env}-upload-lambda"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ─── LOG GROUP: crop-lambda ───────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "crop_lambda" {
  name              = "/aws/lambda/${var.project}-${var.env}-crop-lambda"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ─── SNS TOPIC para notificaciones de alarma ──────────────────────────────────
resource "aws_sns_topic" "dlq_alarm" {
  name = "${var.project}-${var.env}-dlq-alarm-topic"

  tags = var.tags
}

# Suscripción de email (opcional; el correo debe confirmarse manualmente)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.dlq_alarm.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ─── ALARMA: DLQ con mensajes visibles ───────────────────────────────────────
# Si hay aunque sea 1 mensaje en el DLQ → alarma (el profesor lo especifica)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project}-${var.env}-dlq-messages-alarm"
  alarm_description   = "Hay mensajes en el DLQ — revisar errores en crop-lambda"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60   # 60 segundos como indica el diagrama
  statistic           = "Sum"
  threshold           = 0    # Cualquier mensaje dispara la alarma

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [aws_sns_topic.dlq_alarm.arn]
  ok_actions    = [aws_sns_topic.dlq_alarm.arn]

  treat_missing_data = "notBreaching"

  tags = var.tags
}
