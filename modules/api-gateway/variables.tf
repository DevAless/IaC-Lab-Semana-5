# modules/api-gateway/variables.tf

variable "project"                  { type = string }
variable "env"                      { type = string }
variable "upload_lambda_invoke_arn" { type = string }

variable "throttling_rate_limit" {
  description = "Máximo de RPS (10000 en prod, menor en dev/qa)"
  type        = number
  default     = 10000
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
