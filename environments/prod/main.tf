terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend recomendado para prod:
  # backend "s3" {
  #   bucket         = "mi-tfstate-bucket-prod"
  #   key            = "image-processor/prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  env     = "prod"
  project = "image-processor"
  suffix  = "001"

  bucket_name = "${local.project}-${local.env}-images-${local.suffix}"

  common_tags = {
    Project     = local.project
    Environment = local.env
    ManagedBy   = "Terraform"
    Owner       = "tu-nombre"
  }
}

data "aws_caller_identity" "current" {}

# ─── VPC — arquitectura completa (multi-AZ, NAT, SQS endpoint) ───────────────
module "vpc" {
  source = "../../modules/vpc"

  project    = local.project
  env        = local.env
  aws_region = var.aws_region

  vpc_cidr              = "10.2.0.0/16"
  public_subnet_a_cidr  = "10.2.1.0/24"
  public_subnet_b_cidr  = "10.2.2.0/24"
  private_subnet_a_cidr = "10.2.11.0/24"
  private_subnet_b_cidr = "10.2.12.0/24"

  # PROD: arquitectura completa con HA
  enable_nat_gateway  = true   # ~$32/mes por NAT Gateway × 2 = ~$64/mes
  enable_multi_az     = true
  enable_sqs_endpoint = true   # ~$7/mes por AZ × 2 = ~$14/mes

  s3_bucket_name = local.bucket_name
  tags           = local.common_tags
}

module "sqs" {
  source = "../../modules/sqs"

  project       = local.project
  env           = local.env
  s3_bucket_arn = module.s3.bucket_arn
  tags          = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  bucket_name    = local.bucket_name
  env            = local.env
  sqs_queue_arn  = module.sqs.queue_arn
  aws_account_id = data.aws_caller_identity.current.account_id

  # Valores del diagrama para prod
  uploads_expiration_days   = 30
  processed_expiration_days = 90

  sqs_policy_dependency = module.sqs.sqs_policy
  tags                  = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  project       = local.project
  env           = local.env
  s3_bucket_arn = module.s3.bucket_arn
  sqs_queue_arn = module.sqs.queue_arn
  tags          = local.common_tags
}

module "observability" {
  source = "../../modules/observability"

  project            = local.project
  env                = local.env
  dlq_name           = module.sqs.dlq_name
  log_retention_days = 14  # Valor del diagrama
  alarm_email        = var.alarm_email
  tags               = local.common_tags
}

resource "aws_apigatewayv2_api" "placeholder" {
  name          = "${local.project}-${local.env}-api-placeholder"
  protocol_type = "HTTP"
  tags          = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

module "lambda" {
  source = "../../modules/lambda"

  project    = local.project
  env        = local.env

  upload_role_arn = module.iam.upload_lambda_role_arn
  crop_role_arn   = module.iam.crop_lambda_role_arn
  s3_bucket_name  = module.s3.bucket_name
  sqs_queue_arn   = module.sqs.queue_arn

  # PROD: ambas subnets privadas para que Lambda distribuya ENIs en multi-AZ
  private_subnet_ids  = module.vpc.private_subnet_ids
  sg_upload_lambda_id = module.vpc.sg_upload_lambda_id
  sg_crop_lambda_id   = module.vpc.sg_crop_lambda_id

  api_gateway_execution_arn = aws_apigatewayv2_api.placeholder.execution_arn
  enable_vpc          = true
  s3_endpoint_dependency    = module.vpc.s3_endpoint_id

  upload_zip_path = var.upload_zip_path
  crop_zip_path   = var.crop_zip_path

  tags = local.common_tags
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  project                  = local.project
  env                      = local.env
  upload_lambda_invoke_arn = module.lambda.upload_lambda_invoke_arn
  throttling_rate_limit    = 10000  # Valor del diagrama
  log_retention_days       = 14
  tags                     = local.common_tags
}
