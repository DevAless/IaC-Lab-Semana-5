variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alarm_email" {
  type    = string
  default = ""
}

variable "upload_zip_path" {
  type    = string
  default = "../../upload-lambda.zip"
}

variable "crop_zip_path" {
  type    = string
  default = "../../crop-lambda.zip"
}
