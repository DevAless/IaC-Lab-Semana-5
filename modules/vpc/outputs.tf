# modules/vpc/outputs.tf

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "public_subnet_b_id" {
  value = var.enable_multi_az ? aws_subnet.public_b[0].id : null
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = var.enable_multi_az ? aws_subnet.private_b[0].id : null
}

output "private_subnet_ids" {
  value = concat(
    [aws_subnet.private_a.id],
    var.enable_multi_az ? [aws_subnet.private_b[0].id] : []
  )
}

output "sg_upload_lambda_id" {
  value = aws_security_group.upload_lambda.id
}

output "sg_crop_lambda_id" {
  value = aws_security_group.crop_lambda.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
