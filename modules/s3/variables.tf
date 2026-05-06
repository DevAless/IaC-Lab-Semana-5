# modules/s3/variables.tf

variable "bucket_name" {
  description = "Nombre del bucket S3"
  type        = string
}

variable "env" {
  type = string
}

variable "sqs_queue_arn" {
  description = "ARN de la cola SQS para notificaciones S3"
  type        = string
}

variable "sqs_policy_dependency" {
  description = "Dependencia para esperar a que la política SQS esté lista"
  type        = any
  default     = null
}

variable "uploads_expiration_days" {
  description = "Días hasta que expiran objetos en uploads/"
  type        = number
  default     = 30
}

variable "processed_expiration_days" {
  description = "Días hasta que expiran objetos en processed/"
  type        = number
  default     = 90
}

variable "aws_account_id" {
  description = "ID de cuenta AWS"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
