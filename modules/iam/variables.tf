# modules/iam/variables.tf

variable "project"       { type = string }
variable "env"           { type = string }
variable "s3_bucket_arn" { type = string }
variable "sqs_queue_arn" { type = string }
variable "tags"          { type = map(string); default = {} }
