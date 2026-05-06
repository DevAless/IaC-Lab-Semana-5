# modules/s3/outputs.tf

output "bucket_id" {
  value = aws_s3_bucket.images.id
}

output "bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "bucket_name" {
  value = aws_s3_bucket.images.bucket
}
