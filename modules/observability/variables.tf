# modules/observability/variables.tf

variable "project"   { type = string }
variable "env"       { type = string }
variable "dlq_name"  { type = string }

variable "log_retention_days" {
  description = "Días de retención de logs. Dev=3, QA=7, Prod=14"
  type        = number
  default     = 14
}

variable "alarm_email" {
  description = "Email para recibir alertas del DLQ (dejar vacío para omitir)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
