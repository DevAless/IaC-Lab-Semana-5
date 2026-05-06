# modules/vpc/variables.tf

variable "project" {
  description = "Nombre del proyecto"
  type        = string
}

variable "env" {
  description = "Entorno: dev, qa, prod"
  type        = string
}

variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_b_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_a_cidr" {
  type    = string
  default = "10.0.11.0/24"
}

variable "private_subnet_b_cidr" {
  type    = string
  default = "10.0.12.0/24"
}

variable "enable_nat_gateway" {
  description = "Habilitar NAT Gateways (solo PROD). Costo: ~$32/mes c/u."
  type        = bool
  default     = false
}

variable "enable_multi_az" {
  description = "Desplegar segunda AZ (solo PROD para alta disponibilidad)"
  type        = bool
  default     = false
}

variable "enable_sqs_endpoint" {
  description = "Habilitar SQS Interface Endpoint (solo PROD). Costo: ~$7/mes por AZ."
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3 para la política del endpoint"
  type        = string
}

variable "tags" {
  description = "Tags comunes para todos los recursos"
  type        = map(string)
  default     = {}
}
