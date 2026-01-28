#!/bin/bash

set -e

echo "=== Waffle House Index API Deployment ==="

# Check for AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS credentials not configured"
    echo "Please run: aws configure"
    exit 1
fi

# Package Lambda function
echo "📦 Packaging Lambda function..."
cd lambda
./package.sh
cd ..

# Initialize Terraform (first time only)
echo "🔧 Initializing Terraform..."
cd terraform

# Check if this is first run
if [ ! -d ".terraform" ]; then
    echo "First run detected. Creating state bucket and lock table..."

    # Create state bucket and lock table using AWS CLI
    aws s3api create-bucket \
        --bucket whi-terraform-state \
        --region us-east-1 \
        2>/dev/null || echo "State bucket already exists"

    aws s3api put-bucket-versioning \
        --bucket whi-terraform-state \
        --versioning-configuration Status=Enabled \
        2>/dev/null || true

    aws dynamodb create-table \
        --table-name whi-terraform-lock \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region us-east-1 \
        2>/dev/null || echo "Lock table already exists"

    # Wait for table to be active
    echo "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name whi-terraform-lock --region us-east-1

    # Initialize with backend
    terraform init
else
    terraform init -upgrade
fi

# Plan deployment
echo "📋 Planning infrastructure changes..."
terraform plan -out=tfplan

# Apply changes
echo "🚀 Deploying infrastructure..."
terraform apply tfplan

# Get outputs
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "📍 API Endpoints:"
echo "CloudFront URL (recommended): $(terraform output -raw cloudfront_url)"
echo "Direct API Gateway URL: $(terraform output -raw api_gateway_url)"
echo ""
echo "🔍 Example usage:"
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url)
echo "curl \"${CLOUDFRONT_URL}/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50\""
echo ""
echo "📊 Resources created:"
echo "- Lambda Function: $(terraform output -raw lambda_function_name)"
echo "- DynamoDB Table: $(terraform output -raw dynamodb_table_name)"
echo "- CloudFront Distribution: $(terraform output -raw cloudfront_distribution_id)"

cd ..