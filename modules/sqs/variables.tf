# modules/sqs/variables.tf

variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "s3_bucket_arn" {
  description = "ARN del bucket S3 que publicará en la cola"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
