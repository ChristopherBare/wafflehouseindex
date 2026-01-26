# Waffle House Index API - AWS Deployment

This Terraform configuration deploys a serverless Waffle House Index API to AWS with optimal cost and performance.

## Architecture

- **AWS Lambda**: Serverless compute (pay only when used)
- **API Gateway**: REST API endpoints
- **DynamoDB**: Caching layer with TTL (1 hour)
- **CloudFront**: Global CDN for low latency
- **EventBridge**: Scheduled cache refresh every 30 minutes

## Cost Optimization

This architecture minimizes costs through:

1. **Serverless Components**: No idle compute costs
2. **DynamoDB On-Demand**: Pay-per-request pricing
3. **CloudFront Class 100**: Uses only North America/Europe edge locations
4. **Efficient Caching**: Reduces Lambda invocations and web scraping

Estimated monthly cost for moderate usage: **< $5**

## Deployment

### Prerequisites

1. AWS CLI configured with credentials
2. Terraform installed (>= 1.5.0)

### Deploy

```bash
# From repository root
./deploy.sh
```

This script will:
1. Package the Lambda function
2. Create Terraform state bucket and lock table (first run only)
3. Deploy all infrastructure
4. Output the API endpoints

### Manual Deployment

```bash
# Package Lambda
cd lambda
./package.sh
cd ..

# Deploy with Terraform
cd terraform
terraform init
terraform plan
terraform apply
```

## API Endpoints

After deployment, you'll get two URLs:

1. **CloudFront URL** (recommended): `https://[distribution-id].cloudfront.net`
   - Cached globally for best performance
   - Lower latency
   - Reduced Lambda costs

2. **API Gateway URL**: `https://[api-id].execute-api.us-east-1.amazonaws.com/prod`
   - Direct access to Lambda
   - Use for testing or if you need uncached responses

### Available Endpoints

- `GET /api/index/coordinates/?lat={lat}&lon={lon}&radius={radius}`
  - Get WHI for coordinates
  - `radius` is optional (default: 50 miles)

- `GET /api/index/zip/?zip={zip}&radius={radius}`
  - Get WHI for ZIP code
  - `radius` is optional (default: 50 miles)

- `GET /api/health`
  - Health check endpoint

### Example Usage

```bash
# Using CloudFront (recommended)
curl "https://d1234567890.cloudfront.net/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50"

# Using API Gateway directly
curl "https://abcd1234.execute-api.us-east-1.amazonaws.com/prod/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50"
```

## Update Flutter App

After deployment, update your Flutter app to use the CloudFront URL:

1. Get the CloudFront URL from Terraform output
2. Update `lib/main.dart`:
   - Replace `http://10.0.2.2:8000` with your CloudFront URL
   - Remove the `/api` prefix from paths (CloudFront adds it)

## Cache Strategy

- **DynamoDB Cache**: 1 hour TTL for location data
- **CloudFront Cache**: 5 minutes default, 1 hour max
- **Automatic Refresh**: EventBridge triggers cache refresh every 30 minutes

This ensures data freshness while minimizing costs and API calls to the Waffle House website.

## Monitoring

View Lambda logs in CloudWatch:
```bash
aws logs tail /aws/lambda/whi-api --follow
```

## Cleanup

To destroy all resources:
```bash
cd terraform
terraform destroy
```

## Cost Breakdown

With typical usage (1000 requests/day):

- **Lambda**: ~$0.20/month (includes free tier)
- **API Gateway**: ~$0.04/month (includes free tier)
- **DynamoDB**: ~$0.25/month (pay-per-request)
- **CloudFront**: ~$0.10/month (minimal data transfer)
- **Total**: **< $1/month**

## Security

- Lambda has minimal IAM permissions (DynamoDB access only)
- API is public but rate-limited by AWS
- No sensitive data is stored or transmitted
- CORS enabled for browser access