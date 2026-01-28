# DynamoDB table for caching location data
resource "aws_dynamodb_table" "whi_locations_cache" {
  name           = "whi-locations"
  billing_mode   = "PAY_PER_REQUEST"  # No fixed costs, pay only for what you use
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  lifecycle {
    create_before_destroy = false
  }

  tags = {
    Name        = "WHI Locations Cache"
    Environment = "production"
    Project     = "wafflehouseindex"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "whi_lambda_role" {
  name = "whi-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  lifecycle {
    create_before_destroy = false
  }
}

# IAM policy for Lambda
resource "aws_iam_policy" "whi_lambda_policy" {
  name = "whi-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.whi_locations_cache.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  lifecycle {
    create_before_destroy = false
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "whi_lambda_policy_attachment" {
  role       = aws_iam_role.whi_lambda_role.name
  policy_arn = aws_iam_policy.whi_lambda_policy.arn
}

# Lambda function
resource "aws_lambda_function" "whi_api" {
  filename         = "../lambda/whi_handler.zip"
  function_name    = "whi-api"
  role            = aws_iam_role.whi_lambda_role.arn
  handler         = "whi_handler.lambda_handler"
  source_code_hash = filebase64sha256("../lambda/whi_handler.zip")
  runtime         = "python3.11"
  timeout         = 30  # Allow time for web scraping if cache miss
  memory_size     = 256  # Enough for processing location data

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.whi_locations_cache.name
    }
  }

  tags = {
    Name        = "WHI API Lambda"
    Environment = "production"
    Project     = "wafflehouseindex"
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "whi_api" {
  name        = "whi-api"
  description = "Waffle House Index API"

  endpoint_configuration {
    types = ["REGIONAL"]  # Use REGIONAL for CloudFront
  }
}

# API Gateway Resources
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  parent_id   = aws_api_gateway_rest_api.whi_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "index" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "index"
}

resource "aws_api_gateway_resource" "coordinates" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  parent_id   = aws_api_gateway_resource.index.id
  path_part   = "coordinates"
}

resource "aws_api_gateway_resource" "zip" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  parent_id   = aws_api_gateway_resource.index.id
  path_part   = "zip"
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "health"
}

# API Gateway Methods - Coordinates endpoint
resource "aws_api_gateway_method" "coordinates_get" {
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  resource_id   = aws_api_gateway_resource.coordinates.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "coordinates_options" {
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  resource_id   = aws_api_gateway_resource.coordinates.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Methods - ZIP endpoint
resource "aws_api_gateway_method" "zip_get" {
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  resource_id   = aws_api_gateway_resource.zip.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "zip_options" {
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  resource_id   = aws_api_gateway_resource.zip.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Methods - Health endpoint
resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

# Lambda integrations
resource "aws_api_gateway_integration" "coordinates_get" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  resource_id = aws_api_gateway_resource.coordinates.id
  http_method = aws_api_gateway_method.coordinates_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.whi_api.invoke_arn
}

resource "aws_api_gateway_integration" "coordinates_options" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  resource_id = aws_api_gateway_resource.coordinates.id
  http_method = aws_api_gateway_method.coordinates_options.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.whi_api.invoke_arn
}

resource "aws_api_gateway_integration" "zip_get" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  resource_id = aws_api_gateway_resource.zip.id
  http_method = aws_api_gateway_method.zip_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.whi_api.invoke_arn
}

resource "aws_api_gateway_integration" "zip_options" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  resource_id = aws_api_gateway_resource.zip.id
  http_method = aws_api_gateway_method.zip_options.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.whi_api.invoke_arn
}

resource "aws_api_gateway_integration" "health_get" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.whi_api.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.whi_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.whi_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "whi_api" {
  rest_api_id = aws_api_gateway_rest_api.whi_api.id

  depends_on = [
    aws_api_gateway_integration.coordinates_get,
    aws_api_gateway_integration.coordinates_options,
    aws_api_gateway_integration.zip_get,
    aws_api_gateway_integration.zip_options,
    aws_api_gateway_integration.health_get,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.whi_api.id
  rest_api_id   = aws_api_gateway_rest_api.whi_api.id
  stage_name    = "prod"

  # Enable caching for better performance
  cache_cluster_enabled = false  # Set to true if you want API Gateway caching (costs extra)
  cache_cluster_size    = "0.5"  # Smallest size if enabled

  tags = {
    Name        = "WHI API Production"
    Environment = "production"
    Project     = "wafflehouseindex"
  }
}

# CloudFront distribution for caching and global performance
resource "aws_cloudfront_distribution" "whi_api" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "WHI API CloudFront Distribution"
  price_class     = "PriceClass_100"  # Use only North America and Europe edge locations (cheaper)

  origin {
    domain_name = "${aws_api_gateway_rest_api.whi_api.id}.execute-api.us-east-1.amazonaws.com"
    origin_id   = "whi-api-gateway"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "whi-api-gateway"

    forwarded_values {
      query_string = true  # Forward query strings for lat/lon/radius
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300    # Cache for 5 minutes by default
    max_ttl                = 3600   # Maximum 1 hour cache

    compress = true
  }

  # Cache behavior for health endpoint (don't cache)
  ordered_cache_behavior {
    path_pattern     = "/api/health"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "whi-api-gateway"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "WHI API CloudFront"
    Environment = "production"
    Project     = "wafflehouseindex"
  }
}

# EventBridge rule for scheduled cache refresh (every 30 minutes)
resource "aws_cloudwatch_event_rule" "cache_refresh" {
  name                = "whi-cache-refresh"
  description         = "Refresh WHI location cache every 30 minutes"
  schedule_expression = "rate(30 minutes)"
}

resource "aws_cloudwatch_event_target" "cache_refresh" {
  rule      = aws_cloudwatch_event_rule.cache_refresh.name
  target_id = "WHILambdaTarget"
  arn       = aws_lambda_function.whi_api.arn

  input = jsonencode({
    path       = "/api/refresh"
    httpMethod = "GET"
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.whi_api.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cache_refresh.arn
}