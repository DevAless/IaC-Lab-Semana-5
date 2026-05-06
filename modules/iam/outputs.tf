# modules/iam/outputs.tf

output "upload_lambda_role_arn" {
  value = aws_iam_role.upload_lambda.arn
}

output "crop_lambda_role_arn" {
  value = aws_iam_role.crop_lambda.arn
}
