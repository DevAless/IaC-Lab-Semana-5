# environments/dev/variables.tf

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alarm_email" {
  description = "Email para alertas del DLQ"
  type        = string
  default     = ""
}

variable "upload_zip_path" {
  type    = string
  default = "../../upload-lambda.zip"
}

variable "crop_zip_path" {
  type    = string
  default = "../../crop-lambda.zip"
}
