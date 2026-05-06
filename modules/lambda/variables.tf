# modules/lambda/variables.tf

variable "project"              { type = string }
variable "env"                  { type = string }
variable "upload_role_arn"      { type = string }
variable "crop_role_arn"        { type = string }
variable "s3_bucket_name"       { type = string }
variable "sqs_queue_arn"        { type = string }
variable "private_subnet_ids"   { type = list(string) }
variable "sg_upload_lambda_id"  { type = string }
variable "sg_crop_lambda_id"    { type = string }
variable "api_gateway_execution_arn" { type = string }
variable "s3_endpoint_dependency"   { type = any; default = null }

variable "upload_zip_path" {
  description = "Ruta al .zip de la upload-lambda"
  type        = string
  default     = "../../upload-lambda.zip"
}

variable "crop_zip_path" {
  description = "Ruta al .zip de la crop-lambda"
  type        = string
  default     = "../../crop-lambda.zip"
}

variable "tags" {
  type    = map(string)
  default = {}
}
