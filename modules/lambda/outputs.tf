# modules/lambda/outputs.tf

output "upload_lambda_arn" {
  value = aws_lambda_function.upload.arn
}

output "upload_lambda_invoke_arn" {
  value = aws_lambda_function.upload.invoke_arn
}

output "crop_lambda_arn" {
  value = aws_lambda_function.crop.arn
}
