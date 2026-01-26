output "api_gateway_url" {
  description = "API Gateway URL"
  value       = "https://${aws_api_gateway_rest_api.whi_api.id}.execute-api.us-east-1.amazonaws.com/prod"
}

output "cloudfront_url" {
  description = "CloudFront distribution URL (use this for best performance)"
  value       = "https://${aws_cloudfront_distribution.whi_api.domain_name}"
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.whi_api.function_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for cache"
  value       = aws_dynamodb_table.whi_locations_cache.name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.whi_api.id
}