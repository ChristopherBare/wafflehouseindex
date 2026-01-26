# Waffle House Index - AWS Deployment Guide

## Quick Start

Deploy the entire backend to AWS with one command:

```bash
./deploy.sh
```

## Architecture Overview

The backend is deployed as a serverless architecture on AWS:

```
CloudFront (CDN)
    ↓
API Gateway
    ↓
Lambda Function ←→ DynamoDB (Cache)
    ↓
Waffle House Website (Data Source)
```

### Cost Optimization Features

1. **100% Serverless** - No idle compute costs
2. **DynamoDB On-Demand** - Pay only for actual reads/writes
3. **CloudFront Caching** - Reduces Lambda invocations
4. **Scheduled Cache Refresh** - Updates data every 30 minutes
5. **Regional API Gateway** - Lower cost than edge-optimized

**Expected Monthly Cost: < $1-5** (depending on traffic)

## Prerequisites

1. **AWS Account** with credentials configured:
   ```bash
   aws configure
   ```

2. **Terraform** installed (>= 1.5.0):
   ```bash
   # macOS
   brew install terraform

   # Linux
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```

## Deployment Steps

### 1. Deploy Infrastructure

```bash
# From repository root
./deploy.sh
```

This will:
- Create S3 bucket for Terraform state
- Create DynamoDB table for state locking
- Package the Lambda function
- Deploy all AWS resources
- Output the API endpoints

### 2. Update Flutter App

After deployment, update the Flutter app to use your CloudFront URL:

1. Get the CloudFront URL from deployment output:
   ```bash
   cd terraform
   terraform output cloudfront_url
   ```

2. Edit `whi_flutter/lib/config.dart`:
   ```dart
   static const bool useProduction = true;  // Enable production mode
   static const String cloudfrontUrl = "https://YOUR_DISTRIBUTION.cloudfront.net";  // Your URL
   ```

3. Rebuild the Flutter app:
   ```bash
   cd whi_flutter
   flutter run
   ```

## API Endpoints

After deployment, you'll have these endpoints available:

### Primary (CloudFront - Recommended)
```
https://[distribution-id].cloudfront.net/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50
https://[distribution-id].cloudfront.net/api/index/zip/?zip=30303&radius=50
https://[distribution-id].cloudfront.net/api/health
```

### Direct (API Gateway)
```
https://[api-id].execute-api.us-east-1.amazonaws.com/prod/api/index/coordinates/?lat=33.7490&lon=-84.3880
```

## Testing the Deployment

```bash
# Get your CloudFront URL
CLOUDFRONT_URL=$(cd terraform && terraform output -raw cloudfront_url)

# Test the API
curl "$CLOUDFRONT_URL/api/health"
curl "$CLOUDFRONT_URL/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50"
```

## Monitoring

### View Lambda Logs
```bash
aws logs tail /aws/lambda/whi-api --follow
```

### Check DynamoDB Cache
```bash
aws dynamodb get-item \
  --table-name whi-locations \
  --key '{"id": {"S": "locations_cache"}}' \
  --query 'Item.updated_at.S'
```

### CloudFront Cache Statistics
```bash
aws cloudfront get-distribution \
  --id $(cd terraform && terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.DistributionConfig.Comment'
```

## Manual Cache Refresh

The cache automatically refreshes every 30 minutes, but you can trigger it manually:

```bash
CLOUDFRONT_URL=$(cd terraform && terraform output -raw cloudfront_url)
curl "$CLOUDFRONT_URL/api/refresh"
```

## Troubleshooting

### Lambda Timeout
If you see timeout errors, the Lambda might be taking too long to scrape the website:
```bash
cd terraform
# Increase timeout in main.tf (line ~85): timeout = 60
terraform apply
```

### CORS Issues
The Lambda includes CORS headers. If you still have issues:
1. Check browser console for specific CORS errors
2. Ensure you're using the CloudFront URL, not API Gateway directly
3. Clear browser cache

### Cache Not Updating
Check the EventBridge rule is enabled:
```bash
aws events describe-rule --name whi-cache-refresh
```

## Cost Monitoring

Set up a billing alert to monitor costs:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name whi-cost-alert \
  --alarm-description "Alert when WHI API exceeds $5/month" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1
```

## Cleanup

To destroy all AWS resources:
```bash
cd terraform
terraform destroy
```

Note: This will NOT delete the Terraform state bucket or lock table. Delete those manually if needed:
```bash
aws s3 rb s3://whi-terraform-state --force
aws dynamodb delete-table --table-name whi-terraform-lock
```

## Architecture Details

### Lambda Function
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 30 seconds
- **Environment**: DynamoDB table name

### DynamoDB Cache
- **Table**: whi-locations
- **Billing**: On-demand (pay per request)
- **TTL**: 1 hour on cached items
- **Items**: Single cache entry with all locations

### CloudFront
- **Price Class**: 100 (North America & Europe only)
- **Cache TTL**: 5 minutes default, 1 hour max
- **Compression**: Enabled
- **Query String Forwarding**: Enabled

### EventBridge
- **Schedule**: Every 30 minutes
- **Target**: Lambda function /api/refresh endpoint

## Performance

With CloudFront caching:
- **First request**: ~500-1000ms (Lambda cold start + DynamoDB read)
- **Cached requests**: ~50-100ms (CloudFront edge)
- **Cache miss**: ~2-5s (web scraping)

## Security

- Lambda has minimal IAM permissions
- No authentication required (public data)
- Rate limiting via AWS (10,000 requests/second burst)
- No sensitive data stored