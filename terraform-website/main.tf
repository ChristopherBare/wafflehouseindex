########################################
# Providers & Backend
########################################

provider "aws" {
  region = "us-east-1" # CloudFront ACM certs must be in us-east-1
}

terraform {
  backend "s3" {
    bucket         = "whi-terraform-state"
    key            = "website/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "whi-terraform-lock"
  }
  # Cloudflare provider commented out for now
  # required_providers {
  #   cloudflare = {
  #     source  = "cloudflare/cloudflare"
  #     version = "5.5.0"
  #   }
  # }
}

# Cloudflare provider (for DNS validation + CNAMEs)
# provider "cloudflare" {
#   api_token = var.cloudflare_api_token
# }

########################################
# Inputs
########################################

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the website"
  type        = string
  default     = "wafflehouseindex.org"
}

# Hostnames you want on the cert and as CloudFront aliases
locals {
  # Forced to false for now as requested
  use_custom_domain = false # var.cloudflare_api_token != "" && var.cloudflare_zone_id != ""
  domain_names = local.use_custom_domain ? [
    var.domain_name,
    "www.${var.domain_name}",
  ] : []
}

########################################
# Random UUID for dev cache path
########################################

resource "random_uuid" "dev_path" {}

########################################
# S3 Bucket (private origin for CloudFront)
########################################

resource "aws_s3_bucket" "website_bucket" {
  bucket        = "wafflehouseindex-site-bucket"
  force_destroy = true

  tags = {
    Name        = "WHI Site Bucket"
    Environment = "Production"
    Project     = "wafflehouseindex"
  }
}

# Ownership controls
resource "aws_s3_bucket_ownership_controls" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Block public access at bucket level
resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

########################################
# CloudFront: Origin Access Control (OAC)
########################################

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "wafflehouseindex-site-oac"
  description                       = "OAC for WHI Site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

########################################
# ACM Certificate (DNS validation via Cloudflare)
########################################

# resource "aws_acm_certificate" "cf_cert" {
#   count                     = local.use_custom_domain ? 1 : 0
#   domain_name               = local.domain_names[0] # apex
#   subject_alternative_names = slice(local.domain_names, 1, length(local.domain_names))
#   validation_method         = "DNS"
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# Publish ACM DNS validation CNAMEs into Cloudflare (DNS-only)
# resource "cloudflare_dns_record" "acm_validation" {
#   for_each = local.use_custom_domain ? {
#     for dvo in aws_acm_certificate.cf_cert[0].domain_validation_options :
#     dvo.domain_name => {
#       name  = dvo.resource_record_name
#       type  = dvo.resource_record_type
#       value = dvo.resource_record_value
#     }
#   } : {}
#
#   zone_id = var.cloudflare_zone_id
#   name    = each.value.name
#   type    = each.value.type
#   content = each.value.value
#   ttl     = 300
#   proxied = false
# }

# Tell ACM to verify the DNS records
# resource "aws_acm_certificate_validation" "cf_cert" {
#   count                   = local.use_custom_domain ? 1 : 0
#   certificate_arn         = aws_acm_certificate.cf_cert[0].arn
#   validation_record_fqdns = [for r in cloudflare_dns_record.acm_validation : r.name]
# }

########################################
# CloudFront Distribution (uses OAC + custom domains)
########################################

resource "aws_cloudfront_distribution" "website_distribution" {
  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.website_bucket.bucket
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Add custom hostnames as aliases if configured
  aliases = local.domain_names

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.website_bucket.bucket

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Development environment cache path (UUID-based)
  ordered_cache_behavior {
    path_pattern     = "/${random_uuid.dev_path.result}/dev/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.website_bucket.bucket

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use default CloudFront cert for now
  viewer_certificate {
    # acm_certificate_arn      = local.use_custom_domain ? aws_acm_certificate_validation.cf_cert[0].certificate_arn : null
    cloudfront_default_certificate = true # !local.use_custom_domain
    # ssl_support_method       = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # SPA-style routing: map 404/403 to index.html
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  comment = "WHI site via S3 + CloudFront (OAC)"
}

########################################
# S3 Bucket Policy for CloudFront OAC
########################################

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket     = aws_s3_bucket.website_bucket.id
  depends_on = [
    aws_cloudfront_origin_access_control.oac,
    aws_cloudfront_distribution.website_distribution
  ]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowGetObjectFromCloudFrontOAC",
        Effect    = "Allow",
        Principal = { Service = "cloudfront.amazonaws.com" },
        Action    = ["s3:GetObject"],
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website_distribution.arn
          }
        }
      }
    ]
  })
}

########################################
# Cloudflare DNS → CloudFront (apex + www)
########################################

# Apex @ → CloudFront
# resource "cloudflare_dns_record" "apex_to_cf" {
#   count   = local.use_custom_domain ? 1 : 0
#   zone_id = var.cloudflare_zone_id
#   name    = "@"
#   type    = "CNAME"
#   content = aws_cloudfront_distribution.website_distribution.domain_name
#   ttl     = 300
#   proxied = false
# }

# www → CloudFront
# resource "cloudflare_dns_record" "www_to_cf" {
#   count   = local.use_custom_domain ? 1 : 0
#   zone_id = var.cloudflare_zone_id
#   name    = "www"
#   type    = "CNAME"
#   content = aws_cloudfront_distribution.website_distribution.domain_name
#   ttl     = 300
#   proxied = false
# }

########################################
# Outputs
########################################

output "website_bucket_name" {
  value = aws_s3_bucket.website_bucket.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.website_distribution.id
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.website_distribution.domain_name
}

output "website_url_cloudfront_domain" {
  value       = "https://${aws_cloudfront_distribution.website_distribution.domain_name}"
  description = "The CloudFront domain URL"
}

output "custom_domains" {
  value       = local.domain_names
  description = "Custom domains attached to CloudFront"
}

output "dev_path_uuid" {
  value     = random_uuid.dev_path.result
  sensitive = true
}
